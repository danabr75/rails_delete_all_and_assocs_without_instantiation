module RailsDeleteAllAndAssocsWithoutInstantiation
  module DeleteAllAndAssocsWithoutInstantiation
    MATCH_DEPENDENT_ASSOC_VALUE = [
      :destroy,
      'destroy',
      :delete_all,
      'delete_all',
      :destroy_async,
      'destroy_async',
    ]

    # rails interpretation is different than expected:
    # https://makandracards.com/makandra/32175-don-t-forget-automatically-remove-join-records-on-has_many-through-associations
    # 'has_many through, dependent: :destroy' will ONLY destroy first join table.
    def build_through_dependency_chain assoc_name
      reflection = self.reflect_on_association(assoc_name)
      reflection_type  = reflection.class.name
      # actual_assoc_name = reflection.options[:source] || reflection.name
      actual_assoc_name = reflection.name
      if reflection_type == "ActiveRecord::Reflection::ThroughReflection"
        reflection.options[:through]
        return "#{build_through_dependency_chain(reflection.options[:through])}.#{actual_assoc_name}"
      else
        actual_assoc_name.to_s
      end
    end

    def delete_all_and_assocs_without_instantiation_builder models_and_ids_list = {}, errors = [], options = {}
      # necessary for "ActiveRecord::Reflection::ThroughReflection" use-case
      # force_through_destroy_chains = options[:force_destroy_chain] || {}
      # do_not_destroy_self = options[:do_not_destroy] || {}

      current_class = self.name
      current_query = self
      ids = current_query.pluck(:id)
      models_and_ids_list[name] ||= []

      # prevent infinite recursion here.
      ids = ids - models_and_ids_list[self.name]
      if ids.none?
        return models_and_ids_list, errors
      end

      models_and_ids_list[self.name] += ids

      # if do_not_destroy_self != true 
      #   models_and_ids_list[name] += ids
      # end

      # ignore associations that aren't dependent destroyable.
      destroy_association_names = self.reflect_on_all_associations.reject{|v| !MATCH_DEPENDENT_ASSOC_VALUE.include?(v.options&.dig(:dependent)) }.collect{ |v| v.name }


      # associations that we might not necessarilly need to delete, but need to go through
      # in order to find assocations that we DO need to delete.
      pass_through_associations = options[:pass_through_associations] || {}
      destroy_association_names.each do |dependent_assoc_name|
        reflection = self.reflect_on_association(dependent_assoc_name)
        reflection_type  = reflection.class.name
        assoc_klass = reflection.klass
        if reflection_type == "ActiveRecord::Reflection::ThroughReflection"
          # can't destroy directly
          destroy_association_names.delete(dependent_assoc_name)

          # OUR original interpretation of 'has_many through destroy', which destroyed the end-of-chain assocs
          # chain = self.build_through_dependency_chain(dependent_assoc_name)
          # current_chain_level = pass_through_associations
          # chain.split('.').each do |assoc_name_in_chain|
          #   # "_destroy_me: false"s can still be destroyed, from the 'destroy_association_names' list
          #   current_chain_level[assoc_name_in_chain] ||= {_destroy_me: false}
          #   current_chain_level = current_chain_level[assoc_name_in_chain]
          # end
          # # end of chain
          # current_chain_level[:_destroy_me] = true
          chain = self.build_through_dependency_chain(dependent_assoc_name)
        end
      end


      pass_through_associations.keys.each do |assoc_key|
        next if assoc_key == :destroy_me
        if !destroy_association_names.include?(assoc_key)
          destroy_association_names << assoc_key
        end
      end

      # need to avoid infinite recursion, if models are dependent in a circular fashion.
      # (destroy_association_names + pass_through_associations.keys).each do |dependent_assoc_name|
      destroy_association_names.each do |dependent_assoc_name|
        reflection = self.reflect_on_association(dependent_assoc_name)
        reflection_type  = reflection.class.name
        assoc_klass = reflection.klass

        # if reflection_type == "ActiveRecord::Reflection::ThroughReflection"
          # we don't have direct access to query them

        assoc_query = assoc_klass.unscoped

        if !assoc_klass.column_names.include?("id") 
          errors << ["#{self.name} and '#{dependent_assoc_name}' - assoc class is missing 'id' column, is required", ids]
          next
        end

        if reflection.scope&.arity&.nonzero?
          errors << ["#{self.name} and '#{dependent_assoc_name}' - scope has instance parameters", ids]
          next
        elsif reflection.scope
          s = self.reflect_on_association(dependent_assoc_name).scope
          assoc_query = assoc_query.instance_exec(&s)
        end

        specified_primary_key = reflection.options[:primary_key]
        specified_foreign_key = reflection.options[:foreign_key]

        # handle foreign_key
        if specified_foreign_key.nil?
          if reflection.options[:polymorphic]
            assoc_query = assoc_query.where({(dependent_assoc_name.singularize + '_type').to_sym => self.table_name.classify})
            specified_foreign_key = dependent_assoc_name.singularize + "_id"
          elsif reflection.options[:as]
            assoc_query = assoc_query.where({(reflection.options[:as].to_s + '_type').to_sym => self.table_name.classify})
            specified_foreign_key = reflection.options[:as].to_s + "_id"
          else
            specified_foreign_key = self.table_name.singularize + "_id"
          end
        end

        # handle primary key
        if specified_primary_key && specified_primary_key&.to_s != 'id'
          assoc_query = assoc_query.where(specified_foreign_key.to_sym => self.pluck(specified_primary_key))
        else
          assoc_query = assoc_query.where(specified_foreign_key.to_sym => ids)
        end
        # do_not_destroy_self = options[:do_not_destroy] || {}
        dup_options = options.dup
        # no longer necessary
        # dup_options[:do_not_destroy] = !destroy_association_names.include?(dependent_assoc_name)
        # dup_options[:pass_through_associations] = pass_through_associations[dependent_assoc_name]&.reject{|v| v == :_destroy_me}
        models_and_ids_list, errors = assoc_query.delete_all_and_assocs_without_instantiation_builder(models_and_ids_list, errors, dup_options)
      end

      return models_and_ids_list, errors
    end

    def delete_all_and_assocs_without_instantiation options = {}
      current_query = self
      built_deletions, errors = current_query.delete_all_and_assocs_without_instantiation_builder({}, [], options.except(:force))

      if errors.any? && options[:force] != true
        return false, errors
      end

      retry_due_to_errors = []
      retry_to_capture_errors = []

      if options[:verbose]
        puts "DELETION STRUCTURE"
        puts built_deletions.inspect
      end

      ActiveRecord::Base.transaction do
        built_deletions.keys.reverse.each do |class_name|
          begin
            ids = built_deletions[class_name]
            next if ids.none?
            klass = class_name.constantize
            klass.unscoped.where(id: ids).delete_all
          rescue Exception => e
            retry_due_to_errors << class_name
          end
        end

        # ActiveRecord::InvalidForeignKey can cause issues in ordering.
        retry_due_to_errors.reverse.each do |class_name|
          begin
            ids = built_deletions[class_name]
            next if ids.none?
            klass = class_name.constantize
            klass.unscoped.where(id: ids).delete_all
            # if Rails.env.test? || Rails.env.development?
            #   if count = klass.unscoped.where(id: ids).count > 0
            #     raise "INVALID DELETION FOR #{klass.name}, w/ IDs: #{ids}. Count found: #{count}"
            #   end
            # end
          rescue Exception => e
            # ActiveRecord::Base.transaction obscures the actual errors
            # - need to run again outside of block to get actual error
            retry_to_capture_errors << [klass, ids]
            raise ActiveRecord::Rollback
          end
        end
      end

      retry_to_capture_errors.each do |klass, ids|
        begin
          klass.unscoped.where(id: ids).delete_all
          # should never get past this line, we're expecting an error!
          # - if we do, maybe was an intermittent issue. Call ourselves recursively to try again.
          return current_query.delete_all_and_assocs_without_instantiation(options)
        rescue Exception => e
          errors << e.class.to_s + "; " + e.message
        end

      end

      if errors.any? && options[:force] != true
        return false, errors
      end

      return true, built_deletions
    end

    def delete_all_and_assocs_w_i options = {}
      return delete_all_and_assocs_without_instantiation(options)
    end

    def delete_all_and_assocs_w_i! options = {}
      options[:force] = true
      return delete_all_and_assocs_without_instantiation(options)
    end

    def delete_all_and_assocs_without_instantiation! options = {}
      options[:force] = true
      return delete_all_and_assocs_without_instantiation(options)
    end
  end
end