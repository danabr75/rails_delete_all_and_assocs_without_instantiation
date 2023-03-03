# rails_delete_all_and_assocs_without_instantiation
A recursive, class-based implementation of active_records' delete_all command, but able to also delete nested associations without record instantiation (much quicker)

# Install
gem 'rails_delete_all_and_assocs_without_instantiation'

# Ex usage:
  ```
  # Delete all queried users and their dependecies.
  # - if any errors are encountered, the transactions are rolled back
  # no errors detected
  User.where(email: deletable_email_list).delete_all_and_assocs_without_instantiation# => true, hash_of_classes_and_ids
  # errors detected, and returned
  User.where(email: deletable_email_list).delete_all_and_assocs_without_instantiation# => false, errors
  # alias
  User.where(email: deletable_email_list).delete_all_and_assocs_w_i
  ```
  ```
  # Push past any errors to delete as many of the objects as possible
  User.where(email: deletable_email_list).delete_all_and_assocs_without_instantiation!
  User.where(email: deletable_email_list).delete_all_and_assocs_w_i!
  User.where(email: deletable_email_list).delete_all_and_assocs_without_instantiation({force: true})
  ```


# Limitations
All tables and traversed associations must have an 'id' column.

All association definitions on models with custom scopes must not have any parameters. That would require instance-evaluation. An error will be thrown if one is detected.
## Ex
```
class User < ApplicationRecord
  # Works!
  has_many :accounts, -> { order(:created_at) }, dependent: :destroy
  # Will not work!
  has_many :creator_accounts, -> (user_id) { where(creator_id: user_id) }, dependent: :destroy
end
```

# Customization
```
class User
  # This is a way you can do more advanced filtering on association dependencies, and not just wipe everything
  def self.delete_all_and_assocs_without_instantiation_builder models_and_ids_list = {}, errors = [], options = {}
    original_account_ids = models_and_ids_list['Account']
    models_and_ids_list, errors = super(models_and_ids_list, errors, options)
    # we've ignored the deletion command that may or may not have been created by your assoc definition
    models_and_ids_list['Account'] = original_account_ids
    
    query = self.where({}).includes(:accounts).joins(:accounts).where(accounts: {marketable: true})
    account_ids = query.collect{|pro| pro.accounts.map(&:id) }.flatten
    models_and_ids_list, errors = Account.unscoped.where(id: account_ids).delete_all_and_assocs_without_instantiation_builder(models_and_ids_list, errors, options)

    return models_and_ids_list, errors
  end
end
```
