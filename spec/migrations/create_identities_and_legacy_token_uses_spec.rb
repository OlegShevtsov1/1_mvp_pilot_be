RSpec.describe 'Identities and legacy token uses migrations' do
  let(:connection) { ActiveRecord::Base.connection }

  def index?(table, columns, unique:)
    connection.indexes(table).any? { |index| index.columns == columns && index.unique == unique }
  end

  def insert(sql)
    connection.transaction(requires_new: true) { connection.execute(sql) }
  end

  def expect_duplicates_refused(first, second)
    insert("INSERT INTO identities (user_id, provider, uid, created_at, updated_at) VALUES (#{first}, 'google', 'g1', now(), now())")
    insert("INSERT INTO legacy_token_uses (user_id, used_on, created_at, updated_at) VALUES (#{first}, CURRENT_DATE, now(), now())")

    duplicates = [
      "INSERT INTO identities (user_id, provider, uid, created_at, updated_at) VALUES (#{second}, 'google', 'g1', now(), now())",
      "INSERT INTO identities (user_id, provider, uid, created_at, updated_at) VALUES (#{first}, 'google', 'g2', now(), now())",
      "INSERT INTO legacy_token_uses (user_id, used_on, created_at, updated_at) VALUES (#{first}, CURRENT_DATE, now(), now())"
    ]
    duplicates.each { |sql| expect { insert(sql) }.to raise_error(ActiveRecord::RecordNotUnique) }
  end

  it 'creates identities with one user per Google account and one Google link per user' do
    expect(connection.table_exists?(:identities)).to be(true)
    expect(index?(:identities, %w[provider uid], unique: true)).to be(true)
    expect(index?(:identities, %w[user_id provider], unique: true)).to be(true)
    expect(foreign_key?(:identities, 'user_id', 'users')).to be(true)
  end

  it 'creates legacy_token_uses with one row per user per day' do
    expect(connection.table_exists?(:legacy_token_uses)).to be(true)
    expect(index?(:legacy_token_uses, %w[user_id used_on], unique: true)).to be(true)
    expect(index?(:legacy_token_uses, %w[used_on], unique: false)).to be(true)
    expect(foreign_key?(:legacy_token_uses, 'user_id', 'users')).to be(true)
  end

  it 'refuses a second link of the same Google account, a second Google link per user and a second row per day' do
    expect_duplicates_refused(*create_list(:user, 2).map(&:id))
  end

  it 'rejects an identity or a legacy use row without its required columns' do
    user_id = create(:user).id
    rows = {
      "INSERT INTO identities (user_id, provider, uid, created_at, updated_at) VALUES (NULL, 'google', 'g1', now(), now())" => 'user_id',
      "INSERT INTO identities (user_id, provider, uid, created_at, updated_at) VALUES (#{user_id}, NULL, 'g1', now(), now())" => 'provider',
      "INSERT INTO identities (user_id, provider, uid, created_at, updated_at) VALUES (#{user_id}, 'google', NULL, now(), now())" => 'uid',
      "INSERT INTO legacy_token_uses (user_id, used_on, created_at, updated_at) VALUES (NULL, CURRENT_DATE, now(), now())" => 'user_id',
      "INSERT INTO legacy_token_uses (user_id, used_on, created_at, updated_at) VALUES (#{user_id}, NULL, now(), now())" => 'used_on'
    }

    rows.each do |sql, column|
      expect { insert(sql) }.to raise_error(ActiveRecord::NotNullViolation, /#{column}/)
    end
  end

  it 'starts a day at zero uses' do
    user_id = create(:user).id
    count = connection.select_value(
      "INSERT INTO legacy_token_uses (user_id, used_on, created_at, updated_at) VALUES (#{user_id}, CURRENT_DATE, now(), now()) RETURNING uses_count"
    )
    expect(count).to eq(0)
  end

  it 'reverts and reapplies on a database that holds users, projects and tasks, keeping every unique index' do
    task = create(:task)
    other_user_id = create(:user).id
    identities = migration('create_identities')
    legacy_token_uses = migration('create_legacy_token_uses')

    ActiveRecord::Migration.suppress_messages do
      legacy_token_uses.migrate(:down)
      identities.migrate(:down)
      expect(connection.table_exists?(:legacy_token_uses)).to be(false)
      expect(connection.table_exists?(:identities)).to be(false)

      identities.migrate(:up)
      legacy_token_uses.migrate(:up)
    end

    expect(Task.find(task.id).project.user).to eq(task.project.user)
    expect_duplicates_refused(task.project.user_id, other_user_id)
  end
end
