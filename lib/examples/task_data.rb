module Examples
  TaskData = Struct.new(
    :name,
    :description,
    :status
  ).new(
    'Example Task',
    'This is an example task created from seeds',
    'not_started'
  ).freeze
end
