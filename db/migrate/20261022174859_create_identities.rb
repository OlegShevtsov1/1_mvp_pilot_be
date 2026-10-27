# Expand: the Google account linked to a user (ADR-0004, AC-05, AC-06).
# uid is Google's stable account identifier, never the email.
class CreateIdentities < ActiveRecord::Migration[7.2]
  def change
    create_table :identities do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :uid, null: false

      t.timestamps
    end

    add_index :identities, %i[provider uid], unique: true
    add_index :identities, %i[user_id provider], unique: true
  end
end
