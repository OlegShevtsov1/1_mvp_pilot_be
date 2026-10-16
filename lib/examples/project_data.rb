module Examples
  ProjectData = Struct.new(
    :name,
    :description
  ).new(
    'Example Project',
    'This is an example project created from seeds'
  ).freeze
end
