require "rails_helper"

RSpec.describe Reporting::ReportingPatientStatesPerMonth, {type: :model, reporting_spec: true} do
  describe "Associations" do
    it { should belong_to(:patient) }
  end

  def ltfu_patient_ids(month_date: Date.current.beginning_of_month)
    described_class
      .where(htn_care_state: "lost_to_follow_up", month_date: month_date)
      .pluck(:id)
  end

  def under_care_patient_ids(month_date: Date.current.beginning_of_month)
    described_class
      .where(htn_care_state: "under_care", month_date: month_date)
      .pluck(:id)
  end

  context "indicators" do
    describe "htn_care_state" do
      it "marks a dead patient dead" do
        dead_patient = create(:patient, status: Patient.statuses[:dead])
        described_class.refresh
        with_reporting_time_zones do
          expect(described_class.where(htn_care_state: "dead").pluck(:id)).to include(dead_patient.id)
        end
      end

      it "marks a patient registered more than 12 months ago with BP more than 12 months ago as ltfu" do
        patient_registered_13m_ago = Timecop.freeze(13.months.ago) { create(:patient) }
        Timecop.freeze(13.months.ago) { create(:blood_pressure, patient: patient_registered_13m_ago) }

        described_class.refresh
        with_reporting_time_zones do
          expect(ltfu_patient_ids).to include(patient_registered_13m_ago.id)
          expect(under_care_patient_ids).not_to include(patient_registered_13m_ago.id)
        end
      end

      it "marks a patient with no bp as lost to follow up depending on registration date" do
        patient_registered_12m_ago = Timecop.freeze(12.months.ago) { create(:patient) }
        patient_registered_11m_ago = Timecop.freeze(11.months.ago) { create(:patient) }

        described_class.refresh
        with_reporting_time_zones do
          expect(ltfu_patient_ids).to include(patient_registered_12m_ago.id)
          expect(under_care_patient_ids).not_to include(patient_registered_12m_ago.id)

          expect(ltfu_patient_ids).not_to include(patient_registered_11m_ago.id)
          expect(under_care_patient_ids).to include(patient_registered_11m_ago.id)
        end
      end

      it "marks a patient registered long ago, with a recent BP as under care" do
        patient_with_recent_bp = Timecop.freeze(13.months.ago) { create(:patient) }
        Timecop.freeze(11.months.ago) { create(:blood_pressure, patient: patient_with_recent_bp) }

        described_class.refresh
        with_reporting_time_zones do
          expect(ltfu_patient_ids).not_to include(patient_with_recent_bp.id)
          expect(under_care_patient_ids).to include(patient_with_recent_bp.id)
        end
      end

      context "ltfu tests ported from patient_spec.rb" do
        it "bp cutoffs for a year ago" do
          under_care_patient = create(:patient, recorded_at: test_times[:long_ago])
          ltfu_patient = create(:patient, recorded_at: test_times[:long_ago])

          create(:blood_pressure, patient: under_care_patient, recorded_at: test_times[:under_a_year_ago])
          create(:blood_pressure, patient: ltfu_patient, recorded_at: test_times[:over_a_year_ago])

          described_class.refresh

          with_reporting_time_zones do
            expect(ltfu_patient_ids(month_date: test_times[:beginning_of_month])).to include(ltfu_patient.id)
            expect(ltfu_patient_ids(month_date: test_times[:beginning_of_month])).not_to include(under_care_patient.id)
            expect(under_care_patient_ids(month_date: test_times[:beginning_of_month])).to include(under_care_patient.id)
            expect(under_care_patient_ids(month_date: test_times[:beginning_of_month])).not_to include(ltfu_patient.id)
          end
        end

        it "bp cutoffs for now" do
          under_care_patient = create(:patient, recorded_at: test_times[:long_ago])
          ltfu_patient = create(:patient, recorded_at: test_times[:long_ago])

          create(:blood_pressure, patient: under_care_patient, recorded_at: test_times[:end_of_month] - 1.minute)
          create(:blood_pressure, patient: ltfu_patient, recorded_at: test_times[:end_of_month] + 1.minute)

          described_class.refresh
          with_reporting_time_zones do
            expect(ltfu_patient_ids(month_date: test_times[:beginning_of_month])).not_to include(under_care_patient.id)
            expect(ltfu_patient_ids(month_date: test_times[:beginning_of_month])).to include(ltfu_patient.id)
            expect(under_care_patient_ids(month_date: test_times[:beginning_of_month])).not_to include(ltfu_patient.id)
            expect(under_care_patient_ids(month_date: test_times[:beginning_of_month])).to include(under_care_patient.id)
          end
        end

        it "registration cutoffs for a year ago" do
          under_care_patient = create(:patient, recorded_at: test_times[:under_a_year_ago])
          ltfu_patient = create(:patient, recorded_at: test_times[:over_a_year_ago])

          described_class.refresh
          with_reporting_time_zones do
            expect(ltfu_patient_ids(month_date: test_times[:beginning_of_month])).not_to include(under_care_patient.id)
            expect(ltfu_patient_ids(month_date: test_times[:beginning_of_month])).to include(ltfu_patient.id)
            expect(under_care_patient_ids(month_date: test_times[:beginning_of_month])).not_to include(ltfu_patient.id)
            expect(under_care_patient_ids(month_date: test_times[:beginning_of_month])).to include(under_care_patient.id)
          end
        end
      end
    end

    describe "htn_treatment_outcome_in_last_3_months is set to" do
      it "missed_visit if the patient hasn't visited in the last 3 months" do
        patient_1 = create(:patient, recorded_at: test_times[:long_ago])
        create(:encounter, patient: patient_1, encountered_on: test_times[:over_three_months_ago])
        patient_2 = create(:patient, recorded_at: test_times[:long_ago])
        create(:encounter, patient: patient_2, encountered_on: test_times[:under_three_months_ago])
        patient_3 = create(:patient, recorded_at: test_times[:long_ago])
        described_class.refresh

        with_reporting_time_zones do
          expect(described_class.where(htn_treatment_outcome_in_last_3_months: "missed_visit", month_date: test_times[:now]).pluck(:id))
            .to include(patient_1.id, patient_3.id)
          expect(described_class.where(htn_treatment_outcome_in_last_3_months: "missed_visit", month_date: test_times[:now]).pluck(:id))
            .not_to include(patient_2.id)
        end
      end

      it "visited_no_bp if the patient visited, but didn't get a BP taken in the last 3 months" do
        patient_bp_over_3_months = create(:patient, recorded_at: test_times[:long_ago])
        create(:prescription_drug,
          device_created_at: test_times[:now] - 1.month,
          facility: patient_bp_over_3_months.registration_facility,
          patient: patient_bp_over_3_months,
          user: patient_bp_over_3_months.registration_user)
        create(:blood_pressure, patient: patient_bp_over_3_months, recorded_at: test_times[:over_three_months_ago])

        patient_bp_under_3_months = create(:patient, recorded_at: test_times[:long_ago])
        create(:prescription_drug,
          device_created_at: test_times[:now] - 1.month,
          facility: patient_bp_under_3_months.registration_facility,
          patient: patient_bp_under_3_months,
          user: patient_bp_under_3_months.registration_user)
        create(:blood_pressure, patient: patient_bp_under_3_months, recorded_at: test_times[:under_three_months_ago])

        patient_with_no_bp = create(:patient, recorded_at: test_times[:long_ago])
        create(:prescription_drug,
          device_created_at: test_times[:now] - 1.month,
          facility: patient_with_no_bp.registration_facility,
          patient: patient_with_no_bp,
          user: patient_with_no_bp.registration_user)
        described_class.refresh

        with_reporting_time_zones do
          expect(described_class.where(htn_treatment_outcome_in_last_3_months: "visited_no_bp", month_date: test_times[:now]).pluck(:id))
            .to include(patient_bp_over_3_months.id, patient_with_no_bp.id)
          expect(described_class.where(htn_treatment_outcome_in_last_3_months: "visited_no_bp", month_date: test_times[:now]).pluck(:id))
            .not_to include(patient_bp_under_3_months.id)
        end
      end

      it "controlled/uncontrolled if there is a BP measured in the last 3 months that is under/not under control" do
        patient_controlled = create(:patient, recorded_at: test_times[:long_ago])
        create(:blood_pressure, :with_encounter, patient: patient_controlled, recorded_at: test_times[:now] - 1.month, systolic: 139, diastolic: 89)

        patient_uncontrolled = create(:patient, recorded_at: test_times[:long_ago])
        create(:blood_pressure, :with_encounter, patient: patient_uncontrolled, recorded_at: test_times[:now] - 1.months, systolic: 140, diastolic: 90)

        patient_bp_over_3_months = create(:patient, recorded_at: test_times[:long_ago])
        create(:blood_pressure, :with_encounter, patient: patient_bp_over_3_months, recorded_at: test_times[:over_three_months_ago])

        described_class.refresh

        with_reporting_time_zones do
          expect(described_class.where(htn_treatment_outcome_in_last_3_months: "controlled", month_date: test_times[:now]).pluck(:id))
            .to include(patient_controlled.id)
          expect(described_class.where(htn_treatment_outcome_in_last_3_months: "uncontrolled", month_date: test_times[:now]).pluck(:id))
            .to include(patient_uncontrolled.id)
          expect(described_class.where(htn_treatment_outcome_in_last_3_months: %w[uncontrolled controlled], month_date: test_times[:now]).pluck(:id))
            .not_to include(patient_bp_over_3_months.id)
        end
      end
    end
    describe "months_since_registration" do
      it "computes it correctly" do
        patient_1 = create(:patient, recorded_at: test_times[:under_a_year_ago])
        patient_2 = create(:patient, recorded_at: test_times[:over_a_year_ago])
        patient_3 = create(:patient, recorded_at: test_times[:now])
        patient_4 = create(:patient, recorded_at: test_times[:over_three_months_ago])

        described_class.refresh
        with_reporting_time_zones do
          expect(described_class.find_by(id: patient_1.id, month_string: test_times[:month_string]).months_since_registration).to eq 11
          expect(described_class.find_by(id: patient_2.id, month_string: test_times[:month_string]).months_since_registration).to eq 12
          expect(described_class.find_by(id: patient_3.id, month_string: test_times[:month_string]).months_since_registration).to eq 0
          expect(described_class.find_by(id: patient_4.id, month_string: test_times[:month_string]).months_since_registration).to eq 3
        end
      end
    end

    describe "assigned and registered facility regions" do
      it "computes the assigned facility and parent regions correctly" do
        facility = create(:facility, :without_parent_region)

        facility_region = create(:region, name: "f-facility", region_type: "facility", source: facility)
        block_region = create(:region, name: "f-block", region_type: "block")
        district_region = create(:region, name: "f-district", region_type: "district")
        state_region = create(:region, name: "f-state", region_type: "state")

        create(:patient, )
      end
    end

    describe "last_bp_state" do
    end
    describe "patient timeline" do
      it "should have a record for every month between registration and now" do
        # assert on months_since_registration, months_since_bp, months_since_visit
      end
    end
  end
end
