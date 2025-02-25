class CreateSmallTestExperiments < ActiveRecord::Migration[5.2]
  def up
    return unless CountryConfig.current_country?("India") && SimpleServer.env.production?

    Seed::ExperimentSeeder.create_current_experiment(experiment_name: "Small Current Patient July 2021")
    Seed::ExperimentSeeder.create_stale_experiment(
      experiment_name: "Small Stale Patient July 2021",
      start_date: "Jul 28, 2021".to_date,
      end_date: "Jul 30, 2021".to_date
    )
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
