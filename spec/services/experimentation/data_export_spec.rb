require "rails_helper"

RSpec.describe Experimentation::DataExport, type: :model do

  def create_notification(experiment, template, patient, appt)
    create(:notification,
      experiment: experiment,
      message: template.message,
      patient: patient,
      purpose: :experimental_appointment_reminder,
      remind_on: appt.scheduled_date + template.remind_on_in_days.days,
      reminder_template: template,
      status: "sent",
      subject: appt
    )
  end

  describe "#result" do
    it "exports accurate data in the expected format" do
      experiment = create(:experiment, name: "exportable", experiment_type: "current_patients", start_date: 35.days.ago, end_date: 5.days.ago)
      control_group = create(:treatment_group, experiment: experiment, description: "control")
      single_message_group = create(:treatment_group, experiment: experiment,description: "single message")
      single_template = create(:reminder_template, treatment_group: single_message_group, remind_on_in_days: -1, message: "single group message")
      cascade_group = create(:treatment_group, experiment: experiment, description: "cascade group")
      cascade_template1 = create(:reminder_template, treatment_group: single_message_group, remind_on_in_days: -1, message: "cascade 1")
      cascade_template2 = create(:reminder_template, treatment_group: single_message_group, remind_on_in_days: 0, message: "cascade 2")
      cascade_template3 = create(:reminder_template, treatment_group: single_message_group, remind_on_in_days: 3, message: "cascade 3")

      patient1 = create(:patient)
      appt1 = create(:appointment, patient: patient1, scheduled_date: 20.days.ago)
      bp = create(:blood_pressure, device_created_at: 21.days.ago)
      single_message_group.patients << patient1
      create_notification(experiment, single_template, patient1, appt1)
      create(:blood_pressure, patient: patient1, device_created_at: 6.months.ago)

      patient2 = create(:patient)
      appt2 = create(:appointment, patient: patient2, scheduled_date: 22.days.ago)
      cascade_group.patients << patient2
      create_notification(experiment, cascade_template1, patient2, appt2)
      create_notification(experiment, cascade_template2, patient2, appt2)
      create_notification(experiment, cascade_template3, patient2, appt2)

      subject = described_class.new(experiment.name)
      results = subject.results
      pp results
      expect(results.class).to eq Array
    end
  end
end