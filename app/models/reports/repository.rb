require_relative "experiment"
module Reports
  class Repository
    include BustCache
    include Memery
    include Scientist

    def self.use_schema_v2?
      @use_schema_v2 ||= false
    end

    class << self
      attr_writer :use_schema_v2
    end

    def initialize(regions, periods:, reporting_schema_v2: self.class.use_schema_v2?)
      @regions = Array(regions).map(&:region)
      @periods = if periods.is_a?(Period)
        Range.new(periods, periods)
      else
        periods
      end
      @period_type = @periods.first.type
      @reporting_schema_v2 = reporting_schema_v2
      raise ArgumentError, "Quarter periods not supported" if @period_type != :month
      @schema = if reporting_schema_v2?
        SchemaV2.new(@regions, periods: @periods)
      else
        SchemaV1.new(@regions, periods: @periods)
      end

      @bp_measures_query = BPMeasuresQuery.new
      @follow_ups_query = FollowUpsQuery.new
      @no_bp_measure_query = NoBPMeasureQuery.new
      @registered_patients_query = RegisteredPatientsQuery.new
    end

    attr_reader :bp_measures_query
    attr_reader :follow_ups_query
    attr_reader :no_bp_measure_query
    attr_reader :period_type
    attr_reader :periods
    attr_reader :regions
    attr_reader :registered_patients_query
    attr_reader :schema

    def reporting_schema_v2?
      @reporting_schema_v2
    end

    delegate :cache, :logger, to: Rails

    DELEGATED_METHODS = [
      :adjusted_patients_with_ltfu,
      :adjusted_patients_without_ltfu,
      :assigned_patients,
      :complete_monthly_registrations,
      :controlled_rates,
      :controlled,
      :cumulative_assigned_patients,
      :cumulative_registrations,
      :earliest_patient_recorded_at,
      :earliest_patient_recorded_at_period,
      :ltfu_rates,
      :ltfu,
      :missed_visits,
      :missed_visits_with_ltfu,
      :missed_visits_without_ltfu,
      :missed_visits_rate,
      :missed_visits_with_ltfu_rates,
      :missed_visits_without_ltfu_rates,
      :monthly_registrations,
      :uncontrolled_rates,
      :uncontrolled,
      :visited_without_bp_taken,
      :visited_without_bp_taken_rates
    ]

    delegate(*DELEGATED_METHODS, to: :schema)

    alias_method :adjusted_patients, :adjusted_patients_without_ltfu

    # Returns registration counts per region / period counted by registration_user
    memoize def monthly_registrations_by_user
      items = regions.map { |region| RegionEntry.new(region, __method__, group_by: :registration_user_id, period_type: period_type) }
      result = cache.fetch_multi(*items, force: bust_cache?) do |entry|
        registered_patients_query.count(entry.region, period_type, group_by: :registration_user_id)
      end
      result.each_with_object({}) { |(region_entry, counts), hsh|
        hsh[region_entry.region.slug] = counts
      }
    end

    # Returns Follow ups per Region / Period. Takes an optional group_by clause (commonly used to group by `blood_pressures.user_id`)
    memoize def hypertension_follow_ups(group_by: nil)
      items = regions.map { |region| RegionEntry.new(region, __method__, group_by: group_by, period_type: period_type) }
      result = cache.fetch_multi(*items, force: bust_cache?) do |entry|
        follow_ups_query.hypertension(entry.region, period_type, group_by: group_by)
      end
      result.each_with_object({}) { |(region_entry, counts), hsh|
        hsh[region_entry.region.slug] = counts
      }
    end

    memoize def bp_measures_by_user
      items = regions.map { |region| RegionEntry.new(region, __method__, group_by: :user_id, period_type: period_type) }
      result = cache.fetch_multi(*items, force: bust_cache?) do |entry|
        bp_measures_query.count(entry.region, period_type, group_by: :user_id)
      end
      result.each_with_object({}) { |(region_entry, counts), hsh|
        hsh[region_entry.region.slug] = counts
      }
    end
  end
end
