require "rails_helper"

RSpec.describe Reporting::ReportingPatientVisitsPerMonth, {type: :model, reporting_spec: true} do
  describe "Associations" do
    it { should belong_to(:patient) }
  end

  describe "the visit definition" do
    it "considers a BP measurement as a visit" do
      bp = create(:blood_pressure, :with_encounter, recorded_at: test_times[:now])
      described_class.refresh
      with_reporting_time_zones do
        visit = described_class.find_by(patient_id: bp.patient_id, month_date: test_times[:now])
        expect(visit.encounter_facility_id).to eq bp.facility_id
        expect(visit.visited_at).to eq bp.recorded_at
      end
    end

    it "considers a Blood Sugar measurement as a visit" do
      blood_sugar = create(:blood_sugar, :with_encounter, recorded_at: test_times[:now])
      described_class.refresh
      with_reporting_time_zones do
        visit = described_class.find_by(patient_id: blood_sugar.patient_id, month_date: test_times[:now])
        expect(visit.encounter_facility_id).to eq blood_sugar.facility_id
        expect(visit.visited_at).to eq blood_sugar.recorded_at
      end
    end

    it "considers a Prescription Drug creation as a visit" do
      prescription_drug = create(:prescription_drug, device_created_at: test_times[:now])
      described_class.refresh
      with_reporting_time_zones do
        visit = described_class.find_by(patient_id: prescription_drug.patient_id, month_date: test_times[:now])
        expect(visit.visited_at).to eq prescription_drug.device_created_at
      end
    end

    it "considers an Appointment creation as a visit" do
      appointment = create(:appointment, device_created_at: test_times[:now])
      described_class.refresh
      with_reporting_time_zones do
        expect(described_class.where(month_date: test_times[:now]).pluck(:patient_id)).to include(appointment.patient.id)
      end
    end

    it "does not consider Teleconsultation as a visit" do
      create(:teleconsultation, device_created_at: test_times[:now])
      described_class.refresh
      with_reporting_time_zones do
        expect(described_class.find_by(month_date: test_times[:now]).visited_at).to be_nil
      end
    end
  end

  describe "visited_at" do
  end

  describe "months_since_visit" do
  end
end