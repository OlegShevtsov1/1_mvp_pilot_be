# Expand: new table, nothing reads it until the token endpoint ships (ADR-0003).
class CreateOauthApplications < ActiveRecord::Migration[7.2]
  def change
    create_table :oauth_applications do |t|
      t.string :name, null: false
      t.string :uid, null: false
      t.string :secret, null: false
      t.text :redirect_uri
      t.string :scopes, null: false, default: ''
      t.boolean :confidential, null: false, default: true

      t.timestamps
    end

    add_index :oauth_applications, :uid, unique: true
  end
end
