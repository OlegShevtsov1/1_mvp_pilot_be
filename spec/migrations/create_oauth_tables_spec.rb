RSpec.describe 'OAuth tables migrations' do
  let(:connection) { ActiveRecord::Base.connection }

  def unique_index?(table, column)
    connection.indexes(table).any? { |index| index.columns == [ column ] && index.unique }
  end

  it 'creates oauth_applications with a unique index on uid' do
    expect(connection.table_exists?(:oauth_applications)).to be(true)
    expect(unique_index?(:oauth_applications, 'uid')).to be(true)
  end

  it 'creates oauth_access_tokens with unique token and refresh_token and foreign keys to users and applications' do
    expect(connection.table_exists?(:oauth_access_tokens)).to be(true)
    expect(unique_index?(:oauth_access_tokens, 'token')).to be(true)
    expect(unique_index?(:oauth_access_tokens, 'refresh_token')).to be(true)
    expect(foreign_key?(:oauth_access_tokens, 'resource_owner_id', 'users')).to be(true)
    expect(foreign_key?(:oauth_access_tokens, 'application_id', 'oauth_applications')).to be(true)
  end

  it 'rejects an access token without an owner, an application or a token' do
    user_id = create(:user).id
    app_id = connection.select_value(
      "INSERT INTO oauth_applications (name, uid, secret, created_at, updated_at) VALUES ('web', 'uid1', 's', now(), now()) RETURNING id"
    )
    rows = {
      'resource_owner_id' => "(NULL, #{app_id}, 't1', now())",
      'application_id' => "(#{user_id}, NULL, 't2', now())",
      'token' => "(#{user_id}, #{app_id}, NULL, now())"
    }

    rows.each do |column, values|
      expect {
        connection.transaction(requires_new: true) do
          connection.execute(
            "INSERT INTO oauth_access_tokens (resource_owner_id, application_id, token, created_at) VALUES #{values}"
          )
        end
      }.to raise_error(ActiveRecord::NotNullViolation, /#{column}/)
    end
  end

  it 'reverts and reapplies on a database that holds users, projects and tasks' do
    task = create(:task)
    applications = migration('create_oauth_applications')
    access_tokens = migration('create_oauth_access_tokens')

    ActiveRecord::Migration.suppress_messages do
      access_tokens.migrate(:down)
      applications.migrate(:down)
      expect(connection.table_exists?(:oauth_access_tokens)).to be(false)
      expect(connection.table_exists?(:oauth_applications)).to be(false)

      applications.migrate(:up)
      access_tokens.migrate(:up)
    end

    expect(Task.find(task.id).project.user).to eq(task.project.user)
    app_id = connection.select_value(
      "INSERT INTO oauth_applications (name, uid, secret, created_at, updated_at) VALUES ('web', 'uid1', 's', now(), now()) RETURNING id"
    )
    expect {
      connection.execute(
        "INSERT INTO oauth_access_tokens (resource_owner_id, application_id, token, created_at) VALUES (#{task.project.user_id}, #{app_id}, 't1', now())"
      )
    }.not_to raise_error
  end
end
