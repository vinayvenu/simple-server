module Experimentation
  class Experiment < ActiveRecord::Base
    has_many :treatment_groups
    has_many :patients, through: :treatment_groups

    validates :name, presence: true, uniqueness: true
    validates :state, presence: true
    validates :experiment_type, presence: true
    validate :start_date_preceeds_end_date

    enum state: {
      new: "new",
      selecting: "selecting",
      live: "live",
      complete: "complete"
    }, _prefix: true
    enum experiment_type: {
      current_patient_reminder: "current_patient_reminder",
      stale_patient_reminder: "stale_patient_reminder"
    }, _prefix: true

    def group_for(uuid)
      hash = Zlib.crc32(uuid) % treatment_groups.length
      treatment_groups.find_by(index: hash)
    end

    private

    def start_date_preceeds_end_date
      return unless start_date && end_date
      if start_date.nil? || end_date.nil?
        errors.add(:date_range, "start date and end date must be present")
      end
      if start_date > end_date
        errors.add(:date_range, "start date must precede end date")
      end
    end

  end
end