class BloodPressuresPerFacilityPerDay < ApplicationRecord
  def self.refresh
    Scenic.database.refresh_materialized_view(table_name, concurrently: false, cascade: false)
  end

  belongs_to :facility
end