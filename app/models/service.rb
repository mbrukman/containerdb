class Service < ApplicationRecord

  SERVICES = {
    redis: 'tutum/redis',
    postgres: 'postgres',
    mysql: 'mysql'
  }

  validates :name, presence: true
  validates :port, uniqueness: true, presence: true
  validates :service_type, presence: true, inclusion: { in: Service::SERVICES.keys.map(&:to_s) }
  validates :image, presence: true, inclusion: { in: Service::SERVICES.values }, if: :hosted?
  validate :validate_environment_variables

  after_initialize :assign_port, :assign_environment_variables, :assign_image, if: :hosted?
  before_destroy :destroy_container

  has_many :backups

  def backup(inline: false)
    if inline
      BackupJob.perform_now(self.backups.create)
    else
      BackupJob.perform_later(self.backups.create)
    end
  end

  def container
    Docker::Container.get(container_id) if container_id
  end

  def destroy_container
    if container_id.present?
      container.kill!
      container.delete
    end
  rescue Docker::Error::NotFoundError
    nil
  end

  def connection_string
    service.connection_string
  end

  def connection_command
    service.connection_command
  end

  def backup_environment_variables
    service.backup_environment_variables
  end

  def backup_script_path
    service.backup_script_path
  end

  def backup_file_name
    service.backup_file_name
  end

  def can_backup?
    backup_environment_variables.present?
  rescue NotImplementedError
    false
  end

  def container_env
    self.environment_variables.map do |key, value|
      "#{key}=#{value}"
    end
  end

  def service
    @_service ||= "#{service_type.capitalize}Service".constantize.new(self)
  end

  protected

  # @todo handle collisions
  def assign_port
    self.port ||= (rand(65000 - 1024) + 1024)
  end

  def assign_image
    self.image ||= Service::SERVICES[self.service_type.to_sym]
  end

  def assign_environment_variables
    self.environment_variables = service.default_environment_variables.merge(self.environment_variables)
  end

  def validate_environment_variables
    service.required_environment_variables.each do |variable|
      errors.add(:environment_variables, "#{variable} is required") unless environment_variables[variable].present?
    end
  end
end
