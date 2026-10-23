# Contract step 2 of 2 (ADR-0005). Promote in the same cutoff release, after 05.
class RemoveAuthenticationTokenFromUsers < ActiveRecord::Migration[7.2]
  def change
    remove_column :users, :authentication_token, :string
  end
end
