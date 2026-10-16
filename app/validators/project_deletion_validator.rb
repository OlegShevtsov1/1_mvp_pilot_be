class ProjectDeletionValidator < ActiveModel::Validator
  def validate(record)
    if record.tasks.exists?
      record.errors.add(:base, 'Cannot delete record because dependent tasks exist')
    end
  end
end
