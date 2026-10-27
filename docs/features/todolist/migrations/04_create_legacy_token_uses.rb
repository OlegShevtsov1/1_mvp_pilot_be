# Expand: daily count of legacy access token use per user, the evidence for the cutoff (ADR-0005, PRD section 6).
class CreateLegacyTokenUses < ActiveRecord::Migration[7.2]
  def change
    create_table :legacy_token_uses do |t|
      t.references :user, null: false, foreign_key: true
      t.date :used_on, null: false
      t.integer :uses_count, null: false, default: 0

      t.timestamps
    end

    add_index :legacy_token_uses, %i[user_id used_on], unique: true
    add_index :legacy_token_uses, :used_on
  end
end
