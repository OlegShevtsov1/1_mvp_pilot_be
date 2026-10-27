module MigrationHelper
  # Loads db/migrate/*_<name>.rb and returns an instance of its migration class.
  def migration(name)
    path = Dir[Rails.root.join("db/migrate/*_#{name}.rb")].first
    raise "db/migrate/*_#{name}.rb is missing" unless path

    require path
    name.camelize.constantize.new
  end

  def foreign_key?(from_table, column, to_table)
    ActiveRecord::Base.connection.foreign_keys(from_table).any? { |fk| fk.column == column && fk.to_table == to_table }
  end
end

RSpec.configure do |config|
  config.include MigrationHelper, file_path: %r{spec/migrations/}
end
