class ApplicationRecord < ActiveRecord::Base

  # DELETE_ALL_WITHOUT_CALLBACKS_BUILDER__EXPECTED_ASSOCIATIONS


  # DELETE_ALL_AND_ASSOCS_CUSTOM_ASSOC_QUERIES = {
  #   variables: 
  # }

  def self.delete_all_and_assocs_without_instantiation_builder models_and_ids_list = {}, errors = [], options = {}
    puts "#{name}##{__callee__}: #{options.inspect}" if Rails.env.development?
    current_query = self
    ids = current_query.pluck(:id)
    models_and_ids_list[name] ||= []

    # prevent infinite recursion here.
    ids = ids - models_and_ids_list[self.name]
    if ids.none?
      return models_and_ids_list, errors
    end
    models_and_ids_list[name] += ids

    # ignore associations that aren't dependent destroyable.
    association_names = self.reflect_on_all_associations.reject{|v| ![:destroy, 'destroy'].include?(v.options&.dig(:dependent)) }.collect{ |v| v.name }


    requires_custom_finder = []

    # need to avoid infinite recursion, if models are dependent in a circular fashion.
    association_names.each do |dependent_assoc_name|
      reflection = self.reflect_on_association(dependent_assoc_name)
      reflection_type  = reflection.name
      assoc_klass = reflection.klass

      assoc_query = assoc_klass.unscoped
      # Answer.reflections['all_answer_requirement_options'].scope => nil

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

      # reflection = Account.reflect_on_association('programs')
      # reflection.options[:primary_key] => :id
      # reflection.options[:foreign_key] => :answerable_id 

      specified_primary_key = reflection.options[:primary_key]
      specified_foreign_key = reflection.options[:foreign_key]

      # handle foreign_key
      if specified_foreign_key.nil?
        if reflection.options[:polymorphic]
          assoc_query = assoc_query.where({(dependent_assoc_name.singularize + '_type').to_sym => self.name})
          specified_foreign_key = dependent_assoc_name.singularize + "_id"
        elsif reflection.options[:as]
          assoc_query = assoc_query.where({(reflection.options[:as] + '_type').to_sym => self.name})
          specified_foreign_key = reflection.options[:as] + "_id"
        else
          specified_foreign_key = self.name.singularize.underscore + "_id"
        end
      end

      # handle primary key
      if specified_primary_key&.to_s != 'id'
        assoc_query = assoc_query.where(specified_foreign_key.to_sym => self.pluck(specified_primary_key))
      else
        assoc_query = assoc_query.where(specified_foreign_key.to_sym => ids)
      end
      models_and_ids_list, errors = assoc_query.delete_all_without_callbacks_builder(models_and_ids_list, errors, options)

      # elsif [
      #   "ActiveRecord::Reflection::BelongsToReflection",
      #   "ActiveRecord::Reflection::HasOneReflection",
      #   "ActiveRecord::Reflection::HasManyReflection"
      # ].include?(reflection_type)
      # else
      #   raise "invalid use-case. For class: #{self.name} and assoc: #{dependent_assoc_name}, could not determine primary/foreign key relationship"
      # end
    end

    return models_and_ids_list, errors
  end

  def self.delete_all_and_assocs_without_instantiation options = {}
    current_query = self
    built_deletions, errors = current_query.delete_all_and_assocs_without_instantiation_builder({}, [], options.except(:force))

    # Rails.logger.warn("#{name}#delete_all_without_callbacks_via_builder: #{built_deletions}")

    if errors.any?
      puts "Errors encountered: #{errors.size}"
      puts errors.inspect
    end

    if errors.any? && options[:force] != true
      return errors
    end

    built_deletions.each do |class_name, ids|
      next if ids.none?
      klass = class_name.constantize
      klass.unscoped.where(id: ids).delete_all
      # if Rails.env.test? || Rails.env.development?
      #   if count = klass.unscoped.where(id: ids).count > 0
      #     raise "INVALID DELETION FOR #{klass.name}, w/ IDs: #{ids}. Count found: #{count}"
      #   end
      # end
    end

    return built_deletions
  end

  def self.delete_all_and_assocs_w_i options = {}
    return delete_all_and_assocs_without_instantiation(options)
  end

  def self.delete_all_and_assocs_w_i! options = {}
    options[:force] = true
    return delete_all_and_assocs_without_instantiation(options)
  end

  def self.delete_all_and_assocs_without_instantiation! options = {}
    options[:force] = true
    return delete_all_and_assocs_without_instantiation(options)
  end
end