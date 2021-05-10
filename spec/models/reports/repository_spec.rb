require "rails_helper"

RSpec.describe Reports::Repository, type: :model do
  let(:organization) { create(:organization, name: "org-1") }
  let(:user) { create(:admin, :manager, :with_access, resource: organization, organization: organization) }
  let(:facility_group_1) { FactoryBot.create(:facility_group, name: "facility_group_1", organization: organization) }

  let(:july_2020_range) { (Period.month(july_2020.advance(months: -24))..Period.month(july_2020)) }

  let(:june_1_2018) { Time.parse("June 1, 2018 00:00:00+00:00") }
  let(:june_1_2020) { Time.parse("June 1, 2020 00:00:00+00:00") }
  let(:june_30_2020) { Time.parse("June 30, 2020 00:00:00+00:00") }
  let(:july_2020) { Time.parse("July 15, 2020 00:00:00+00:00") }
  let(:jan_2019) { Time.parse("January 1st, 2019 00:00:00+00:00") }
  let(:jan_2020) { Time.parse("January 1st, 2020 00:00:00+00:00") }
  let(:july_2018) { Time.parse("July 1st, 2018 00:00:00+00:00") }
  let(:july_2020) { Time.parse("July 1st, 2020 00:00:00+00:00") }

  def refresh_views
    ActiveRecord::Base.transaction do
      LatestBloodPressuresPerPatientPerMonth.refresh
      LatestBloodPressuresPerPatientPerQuarter.refresh
      PatientRegistrationsPerDayPerFacility.refresh
    end
  end

  context "earliest patient record" do
    it "returns the earliest between both assigned and registered if both exist" do
      facility_1, facility_2 = FactoryBot.create_list(:facility, 2, facility_group: facility_group_1)
      region = facility_group_1.region
      other_facility = create(:facility)
      _patient_1 = create(:patient, recorded_at: july_2018, assigned_facility: facility_2)
      _patient_2 = create(:patient, recorded_at: june_1_2018, assigned_facility: other_facility, registration_facility: facility_1)
      facility_3 = create(:facility)
      region_with_no_patients = facility_3.region

      repo = Reports::Repository.new(facility_group_1.region, periods: jan_2019.to_period)
      expect(repo.earliest_patient_recorded_at[region.slug]).to eq(june_1_2018)
      expect(repo.earliest_patient_recorded_at[region_with_no_patients.slug]).to be_nil
    end
  end

  context "counts and rates" do
    it "gets assigned and registration counts for single region" do
      facilities = FactoryBot.create_list(:facility, 2, facility_group: facility_group_1).sort_by(&:slug)
      facility_1, facility_2 = facilities.take(2)

      default_attrs = {registration_facility: facility_1, assigned_facility: facility_1, registration_user: user}
      _facility_1_registered = create_list(:patient, 2, default_attrs.merge(full_name: "controlled", recorded_at: jan_2019 + 1.day))
      create_list(:patient, 2, full_name: "controlled", recorded_at: jan_2019.advance(months: -4), assigned_facility: facility_1, registration_user: user)
      _facility_2_registered = create(:patient, full_name: "other facility", recorded_at: jan_2019, assigned_facility: facility_2, registration_user: user)

      repo = Reports::Repository.new(facility_1.region, periods: jan_2019.to_period)
      expected = {
        facility_1.slug => {
          jan_2019.to_period => 2
        }
      }
      expect(repo.assigned_patients_count).to eq(expected)
      expect(repo.registration_counts).to eq(expected)
    end

    it "gets assigned and registration counts for a range of periods" do
      facilities = FactoryBot.create_list(:facility, 2, facility_group: facility_group_1).sort_by(&:slug)
      facility_1, facility_2 = facilities.take(2)

      default_attrs = {registration_facility: facility_1, assigned_facility: facility_1, registration_user: user}
      _facility_1_registered_in_jan_2019 = create_list(:patient, 2, default_attrs.merge(recorded_at: jan_2019))
      _facility_1_registered_in_august_2018 = create_list(:patient, 2, default_attrs.merge(recorded_at: Time.parse("August 10th 2018")))
      _facility_2_registered = create(:patient, full_name: "other facility", recorded_at: jan_2019, assigned_facility: facility_2, registration_user: user)

      refresh_views

      slug = facility_1.slug
      repo = Reports::Repository.new(facility_1.region, periods: (july_2018.to_period..july_2020.to_period))
      service = ControlRateService.new(facility_1.region, periods: (july_2018.to_period..july_2020.to_period))
      result = service.call

      # ensure we match the ControlRateService results, otherwise things could change in the reports
      expect(repo.registration_counts[slug]).to eq(result[:registrations])
      expect(repo.assigned_patients_count[slug]).to eq(result[:assigned_patients])

      expect(repo.assigned_patients_count[slug][Period.month("August 2018")]).to eq(2)
      expect(repo.assigned_patients_count[slug][Period.month("Jan 2019")]).to eq(2)
      expect(repo.assigned_patients_count[slug][july_2020]).to eq(0)
      expect(repo.registration_counts[slug][Period.month("August 2018")]).to eq(2)
      expect(repo.registration_counts[slug][Period.month("Jan 2019")]).to eq(2)
      expect(repo.registration_counts[slug][july_2020]).to eq(0)
    end

    it "can count registrations and cumulative registrations by user" do
      facilities = FactoryBot.create_list(:facility, 2, facility_group: facility_group_1).sort_by(&:slug)
      facility_1, facility_2 = facilities.take(2)
      user_2 = create(:user)

      default_attrs = {registration_facility: facility_1, assigned_facility: facility_1, registration_user: user}
      jan_1_2018 = Period.month("January 1 2018")
      _facility_1_registered_before_repository_range = create_list(:patient, 2, default_attrs.merge(recorded_at: jan_1_2018.value))
      _facility_1_registered_in_jan_2019 = create_list(:patient, 2, default_attrs.merge(recorded_at: jan_2019))
      _facility_1_registered_in_august_2018 = create_list(:patient, 2, default_attrs.merge(recorded_at: Time.parse("August 10th 2018")))
      _user_2_registered = create(:patient, full_name: "other user", recorded_at: jan_2019, registration_facility: facility_1, registration_user: user_2)

      refresh_views

      repo = Reports::Repository.new(facility_1.region, periods: (july_2018.to_period..july_2020.to_period))
      expect(repo.registration_counts_by_user[facility_1.slug][jan_2019.to_period][user.id]).to eq(2)
      expect(repo.registration_counts_by_user[facility_1.slug][jan_2019.to_period][user_2.id]).to eq(1)
      expect(repo.cumulative_registration_counts_by_user[facility_1.slug][july_2018.to_period][user.id]).to eq(2)
      expect(repo.cumulative_registration_counts_by_user[facility_1.slug][july_2020.to_period][user.id]).to eq(6)
      expect(repo.cumulative_registration_counts_by_user[facility_1.slug][july_2018.to_period][user_2.id]).to eq(0)
      expect(repo.cumulative_registration_counts_by_user[facility_1.slug][jan_2019.to_period][user_2.id]).to eq(1)
      expect(repo.cumulative_registration_counts_by_user[facility_1.slug][july_2020.to_period][user_2.id]).to eq(1)
    end

    it "gets registration and assigned patient counts for brand new regions with no data" do
      facility_1 = FactoryBot.create(:facility, facility_group: facility_group_1)
      repo = Reports::Repository.new(facility_1.region, periods: july_2020_range)
      expect(repo.registration_counts).to eq({facility_1.slug => {}})
      expect(repo.controlled_patients_count).to eq({facility_1.slug => {}})
      expect(repo.controlled_patients_rate).to eq({facility_1.slug => {}})
    end

    it "gets controlled counts and rates for single region" do
      facilities = FactoryBot.create_list(:facility, 2, facility_group: facility_group_1).sort_by(&:slug)
      facility_1, facility_2 = facilities.take(2)
      facility_1_controlled = create_list(:patient, 2, full_name: "controlled", recorded_at: jan_2019, assigned_facility: facility_1, registration_user: user)
      facility_1_uncontrolled = create_list(:patient, 2, full_name: "uncontrolled", recorded_at: jan_2019, assigned_facility: facility_1, registration_user: user)
      facility_2_controlled = create(:patient, full_name: "other facility", recorded_at: jan_2019, assigned_facility: facility_2, registration_user: user)
      Timecop.freeze(jan_2020) do
        (facility_1_controlled << facility_2_controlled).map do |patient|
          create(:blood_pressure, :under_control, facility: facility_1, patient: patient, recorded_at: 15.days.ago, user: user)
        end
        facility_1_uncontrolled.map do |patient|
          create(:blood_pressure, :hypertensive, facility: facility_1, patient: patient, recorded_at: 15.days.ago)
        end
      end
      refresh_views

      expected_counts = {
        facility_1.slug => {
          jan_2020.to_period => 2
        }
      }
      expected_rates = {
        facility_1.slug => {
          jan_2020.to_period => 50
        }
      }
      repo = Reports::Repository.new(facility_1.region, periods: jan_2020.to_period)
      (jan_2019.to_period..jan_2020.to_period).each do |period|
        count = repo.cumulative_assigned_patients_count[facility_1.slug][period]
        expect(count).to eq(4), "expected 4 assigned patients for #{period} but got #{count}"
      end
      expect(repo.controlled_patients_count).to eq(expected_counts)
      expect(repo.controlled_patients_rate).to eq(expected_rates)
    end

    it "gets controlled counts and rates for one month" do
      facilities = FactoryBot.create_list(:facility, 3, facility_group: facility_group_1).sort_by(&:slug)
      facility_1, facility_2, facility_3 = *facilities.take(3)
      regions = facilities.map(&:region)

      facility_1_controlled = create_list(:patient, 2, full_name: "controlled", recorded_at: jan_2019, assigned_facility: facility_1, registration_user: user)
      facility_1_uncontrolled = create_list(:patient, 2, full_name: "uncontrolled", recorded_at: jan_2019, assigned_facility: facility_1, registration_user: user)
      facility_2_controlled = create(:patient, full_name: "other facility", recorded_at: jan_2019, assigned_facility: facility_2, registration_user: user)

      Timecop.freeze(jan_2020) do
        (facility_1_controlled << facility_2_controlled).map do |patient|
          create(:blood_pressure, :under_control, facility: facility_1, patient: patient, recorded_at: 15.days.ago, user: user)
        end
        facility_1_uncontrolled.map do |patient|
          create(:blood_pressure, :hypertensive, facility: facility_1, patient: patient, recorded_at: 15.days.ago)
        end
      end

      refresh_views

      jan = Period.month(jan_2020)
      repo = Reports::Repository.new(regions, periods: Period.month(jan))
      controlled = repo.controlled_patients_count
      uncontrolled = repo.uncontrolled_patients_count
      expect(controlled[facility_1.slug][jan]).to eq(2)
      expect(controlled[facility_2.slug][jan]).to eq(1)
      expect(controlled[facility_3.slug][jan]).to eq(0)
      expect(uncontrolled[facility_1.slug][jan]).to eq(2)
      expect(uncontrolled[facility_2.slug][jan]).to eq(0)
      expect(uncontrolled[facility_3.slug][jan]).to eq(0)
    end

    it "gets controlled info for range of month periods" do
      facilities = FactoryBot.create_list(:facility, 3, facility_group: facility_group_1)
      facility_1, facility_2, facility_3 = *facilities.take(3)
      regions = facilities.map(&:region)

      controlled_in_jan_and_june = create_list(:patient, 2, full_name: "controlled", recorded_at: jan_2019, assigned_facility: facility_1, registration_user: user)
      uncontrolled_in_jan = create_list(:patient, 2, full_name: "uncontrolled", recorded_at: jan_2019, assigned_facility: facility_2, registration_user: user)
      controlled_just_for_june = create(:patient, full_name: "just for june", recorded_at: jan_2019, assigned_facility: facility_1, registration_user: user)
      patient_from_other_facility = create(:patient, full_name: "other facility", recorded_at: jan_2019, assigned_facility: create(:facility), registration_user: user)

      Timecop.freeze(jan_2020) do
        controlled_in_jan_and_june.map do |patient|
          create(:blood_pressure, :hypertensive, facility: facility_1, patient: patient, recorded_at: 3.days.from_now, user: user)
          create(:blood_pressure, :under_control, facility: facility_1, patient: patient, recorded_at: 4.days.from_now, user: user)
        end
        uncontrolled_in_jan.map { |patient| create(:blood_pressure, :hypertensive, facility: facility_2, patient: patient, recorded_at: 4.days.from_now) }
        create(:blood_pressure, :under_control, facility: patient_from_other_facility.assigned_facility, patient: patient_from_other_facility, recorded_at: 4.days.from_now)
      end

      Timecop.freeze(june_1_2020) do
        controlled_in_jan_and_june.map do |patient|
          create(:blood_pressure, :under_control, facility: facility_1, patient: patient, recorded_at: 2.days.ago, user: user)
          create(:blood_pressure, :hypertensive, facility: facility_1, patient: patient, recorded_at: 4.days.ago, user: user)
          create(:blood_pressure, :hypertensive, facility: facility_1, patient: patient, recorded_at: 35.days.ago, user: user)
        end

        create(:blood_pressure, :under_control, facility: facility_3, patient: controlled_just_for_june, recorded_at: 4.days.ago, user: user)

        uncontrolled_in_june = create_list(:patient, 5, recorded_at: 4.months.ago, assigned_facility: facility_1, registration_user: user)
        uncontrolled_in_june.map do |patient|
          create(:blood_pressure, :hypertensive, facility: facility_1, patient: patient, recorded_at: 1.days.ago, user: user)
          create(:blood_pressure, :under_control, facility: facility_1, patient: patient, recorded_at: 2.days.ago, user: user)
        end
      end

      refresh_views

      start_range = july_2020.advance(months: -24)
      range = (Period.month(start_range)..Period.month(july_2020))
      repo = Reports::Repository.new(regions, periods: range)
      result = repo.controlled_patients_count

      facility_1_results = result[facility_1.slug]
      range.each do |period|
        expect(facility_1_results[period]).to_not be_nil
      end
      expect(facility_1_results[Period.month(jan_2020)]).to eq(controlled_in_jan_and_june.size)
      expect(facility_1_results[Period.month(june_1_2020)]).to eq(3)
    end

    it "excludes dead patients from control info" do
      facility_1 = FactoryBot.create_list(:facility, 1, facility_group: facility_group_1).first
      facility_1_controlled = create_list(:patient, 1, full_name: "controlled", recorded_at: jan_2019, assigned_facility: facility_1, registration_user: user)
      facility_1_controlled_dead = create_list(:patient, 1, status: :dead, full_name: "controlled", recorded_at: jan_2019, assigned_facility: facility_1, registration_user: user)

      Timecop.freeze(jan_2020) do
        facility_1_controlled.concat(facility_1_controlled_dead).map do |patient|
          create(:blood_pressure, :under_control, facility: facility_1, patient: patient, recorded_at: 15.days.ago, user: user)
        end
      end

      refresh_views
      jan = Period.month(jan_2020)
      repo = Reports::Repository.new(facility_1, periods: Period.month(jan))
      controlled = repo.controlled_patients_count
      uncontrolled = repo.uncontrolled_patients_count

      region = facility_1.region
      expect(controlled[region.slug].fetch(jan)).to eq(1)
      expect(uncontrolled[region.slug].fetch(jan)).to eq(0)
    end

    it "gets visit without BP taken counts without LTFU" do
      facility_1 = FactoryBot.create_list(:facility, 1, facility_group: facility_group_1).first
      # Since we are reporting for Jan 2020, this patient is lost to follow up -- they have been registered for 12 months but have no BPs taken
      visit_with_no_bp_and_ltfu = create(:patient, full_name: "visit_with_no_bp_and_ltfu", recorded_at: jan_2019, assigned_facility: facility_1, registration_user: user)
      # This user is NOT lost to follow up, as they have not been registered over 12 months
      visit_with_no_bp_and_not_ltfu = create(:patient, full_name: "visit_with_no_bp_and_not_ltfu", recorded_at: "June 2019", assigned_facility: facility_1, registration_user: user)
      visit_with_bp = create(:patient, full_name: "visit_with_bp", recorded_at: jan_2019, assigned_facility: facility_1, registration_user: user)

      Timecop.freeze(jan_2020) do
        create(:appointment, patient: visit_with_no_bp_and_ltfu, facility: facility_1, user: user)
        create(:blood_sugar, patient: visit_with_no_bp_and_not_ltfu, facility: facility_1, user: user)
        create(:blood_pressure, :under_control, facility: facility_1, patient: visit_with_bp, user: user)
      end

      refresh_views
      jan = Period.month(jan_2020)
      repo = Reports::Repository.new(facility_1, periods: jan)
      expect(repo.visited_without_bp_taken[facility_1.region.slug][jan]).to eq(1)
    end
  end

  context "caching" do
    let(:facility_1) { create(:facility, name: "facility-1") }

    it "creates cache keys" do
      repo = Reports::Repository.new(facility_1, periods: Period.month("June 1 2019")..Period.month("Jan 1 2020"))
      cache_keys = repo.send(:cache_entries, :controlled).map(&:cache_key)
      cache_keys.each do |key|
        expect(key).to include("controlled")
      end
    end

    it "memoizes calls to queries" do
      controlled_in_jan = create_list(:patient, 2, full_name: "controlled", recorded_at: jan_2019, assigned_facility: facility_1, registration_user: user)
      Timecop.freeze(jan_2020) do
        controlled_in_jan.map do |patient|
          create(:blood_pressure, :under_control, facility: facility_1, patient: patient, recorded_at: 4.days.from_now, user: user)
        end
      end
      refresh_views

      repo = Reports::Repository.new(facility_1.region, periods: july_2020_range)

      allow(repo).to receive(:region_period_cached_query).and_call_original
      expect(repo).to receive(:region_period_cached_query).with(:controlled_patients_count).exactly(1).times.and_call_original

      3.times { _result = repo.controlled_patients_count }
      3.times { _result = repo.controlled_patients_rate }
    end

    it "will not ignore memoization when bust_cache is true" do
      controlled_in_jan = create_list(:patient, 2, full_name: "controlled", recorded_at: jan_2019, assigned_facility: facility_1, registration_user: user)
      Timecop.freeze(jan_2020) do
        controlled_in_jan.map do |patient|
          create(:blood_pressure, :under_control, facility: facility_1, patient: patient, recorded_at: 4.days.from_now, user: user)
        end
      end
      refresh_views

      RequestStore[:bust_cache] = true
      repo = Reports::Repository.new(facility_1.region, periods: july_2020_range)
      expect(repo).to receive(:region_period_cached_query).with(:controlled_patients_count).exactly(1).times

      3.times { _result = repo.controlled_patients_count }
    end
  end

  context "legacy control specs" do
    it "returns same results as ControlRateService" do
      facilities = FactoryBot.create_list(:facility, 3, facility_group: facility_group_1)
      facility_1, facility_2, facility_3 = *facilities.take(3)

      _ltfu_patient = create(:patient, recorded_at: 2.years.ago, assigned_facility: facility_1)
      _dead_patient = create(:patient, full_name: "dead", recorded_at: jan_2019, status: :dead, assigned_facility: facility_1, registration_user: user)
      controlled_in_jan_and_june = create_list(:patient, 2, full_name: "controlled", recorded_at: jan_2019, assigned_facility: facility_1, registration_user: user)
      uncontrolled_in_jan = create_list(:patient, 2, full_name: "uncontrolled", recorded_at: jan_2019, assigned_facility: facility_2, registration_user: user)
      controlled_just_for_june = create(:patient, full_name: "just for june", recorded_at: jan_2019, assigned_facility: facility_1, registration_user: user)
      patient_from_other_facility = create(:patient, full_name: "other facility", recorded_at: jan_2019, assigned_facility: create(:facility), registration_user: user)

      Timecop.freeze(jan_2020) do
        controlled_in_jan_and_june.map do |patient|
          create(:blood_pressure, :hypertensive, facility: facility_1, patient: patient, recorded_at: 3.days.from_now, user: user)
          create(:blood_pressure, :under_control, facility: facility_1, patient: patient, recorded_at: 4.days.from_now, user: user)
        end
        uncontrolled_in_jan.map { |patient| create(:blood_pressure, :hypertensive, facility: facility_2, patient: patient, recorded_at: 4.days.from_now) }
        create(:blood_pressure, :under_control, facility: patient_from_other_facility.assigned_facility, patient: patient_from_other_facility, recorded_at: 4.days.from_now)
      end

      Timecop.freeze(june_1_2020) do
        controlled_in_jan_and_june.map do |patient|
          create(:blood_pressure, :under_control, facility: facility_1, patient: patient, recorded_at: 2.days.ago, user: user)
          create(:blood_pressure, :hypertensive, facility: facility_1, patient: patient, recorded_at: 4.days.ago, user: user)
          create(:blood_pressure, :hypertensive, facility: facility_1, patient: patient, recorded_at: 35.days.ago, user: user)
        end

        create(:blood_pressure, :under_control, facility: facility_3, patient: controlled_just_for_june, recorded_at: 4.days.ago, user: user)

        uncontrolled_in_june = create_list(:patient, 5, recorded_at: 4.months.ago, assigned_facility: facility_1, registration_user: user)
        uncontrolled_in_june.map do |patient|
          create(:blood_pressure, :hypertensive, facility: facility_1, patient: patient, recorded_at: 1.days.ago, user: user)
          create(:blood_pressure, :under_control, facility: facility_1, patient: patient, recorded_at: 2.days.ago, user: user)
        end
      end

      refresh_views

      start_range = july_2020.advance(months: -24)
      range = (Period.month(start_range)..Period.month(july_2020))
      repo = Reports::Repository.new(facility_1, periods: range)
      service_result = ControlRateService.new(facility_1, periods: range).call
      slug = facility_1.slug

      range.each do |period|
        expect(repo.adjusted_patient_counts[slug][period]).to eq(service_result[:adjusted_patient_counts][period])
        expect(repo.adjusted_patient_counts_with_ltfu[slug][period]).to eq(service_result[:adjusted_patient_counts_with_ltfu][period])
        expect(repo.adjusted_patient_counts_with_ltfu[slug][period]).to eq(service_result[:adjusted_patient_counts_with_ltfu][period])

        expect(repo.cumulative_assigned_patients_count[slug][period]).to eq(service_result[:cumulative_assigned_patients][period])
        expect(repo.controlled_patients_rate[slug][period]).to eq(service_result[:controlled_patients_rate][period])
        expect(repo.uncontrolled_patients_rate[slug][period]).to eq(service_result[:uncontrolled_patients_rate][period])
      end
    end

    it "gets same results as RegionService for missed_visits" do
      may_1 = Time.parse("May 1st, 2020")
      may_15 = Time.parse("May 15th, 2020")
      facility = create(:facility, facility_group: facility_group_1)
      _patient_missed_visit_1 = FactoryBot.create(:patient, assigned_facility: facility, recorded_at: Time.parse("December 1st 2010"))
      _patient_missed_visit_2 = FactoryBot.create(:patient, assigned_facility: facility, recorded_at: jan_2020)
      patient_without_bp = FactoryBot.create(:patient, assigned_facility: facility, recorded_at: jan_2020)
      patient_with_bp = FactoryBot.create(:patient, assigned_facility: facility, recorded_at: jan_2020)
      _appointment_1 = create(:appointment, creation_facility: facility, scheduled_date: may_1, device_created_at: may_1, patient: patient_without_bp)
      _appointment_2 = create(:appointment, creation_facility: facility, scheduled_date: may_15, device_created_at: may_15, patient: patient_with_bp)
      create(:blood_pressure, :under_control, facility: facility, patient: patient_with_bp, recorded_at: may_15)

      service = Reports::RegionService.new(region: facility, period: july_2020.to_period)
      repo = Reports::Repository.new(facility.region, periods: service.range)
      legacy_results = service.call
      facility_results = repo.missed_visits[facility.slug]

      expect(legacy_results[:missed_visits].size).to eq(service.range.entries.size)
      expect(facility_results.size).to eq(service.range.entries.size)
      expect(facility_results).to eq(legacy_results[:missed_visits])
    end
  end
end
