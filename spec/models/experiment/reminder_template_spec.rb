require "rails_helper"

RSpec.describe Experiment::ReminderTemplate, type: :model do
  describe "associations" do
    it { should belong_to(:reminder_experiment) }
    it { should have_many(:appointment_reminders) }
  end
end
