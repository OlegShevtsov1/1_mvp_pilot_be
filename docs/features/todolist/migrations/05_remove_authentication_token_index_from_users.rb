# Contract step 1 of 2 (ADR-0005). Promote ONLY in the cutoff release, after no legacy use was seen for 7 days
# and the code no longer reads users.authentication_token.
class RemoveAuthenticationTokenIndexFromUsers < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    remove_index :users, :authentication_token, algorithm: :concurrently
  end
end
