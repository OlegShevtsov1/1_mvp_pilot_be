module Examples
  UserData = Struct.new(
    :email,
    :password
  ).new(
    'user@example.com',
    'password'
  ).freeze
end
