class CreatePatientStatesOverTime < ActiveRecord::Migration[5.2]
  def change
    create_view :patient_states_over_time, materialized: true
  end
end