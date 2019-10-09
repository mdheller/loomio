namespace :loomio do
  task generate_test_error: :environment do
    raise "this is a generated test error"
  end

  task :version do
    puts Loomio::Version.current
  end

  task generate_static_error_pages: :environment do
    [400, 404, 410, 417, 422, 429, 500].each do |code|
      File.open("public/#{code}.html", "w") do |f|
        f << "<!-- This file is automatically generated by rake loomio:generate_static_error_pages -->\n"
        f << "<!-- Don't make changes here; they will be overwritten. -->\n"
        f << ApplicationController.new.render_to_string(
          template: "errors/#{code}",
          layout: "basic"
        )
      end
    end
  end

  task hourly_tasks: :environment do
    UserService.delay.delete_many_spam(ENV['DELETE_MANY_SPAM'])

    PollService.delay.expire_lapsed_polls
    PollService.delay.publish_closing_soon

    if ENV['EMAIL_CATCH_UP_WEEKLY']
      SendWeeklyCatchUpEmailJob.perform_later
    else
      SendDailyCatchUpEmailJob.perform_later
    end

    AnnouncementService.delay.resend_pending_invitations
    LocateUsersAndGroupsJob.perform_later
    if (Time.now.hour == 0)
      UsageReportService.send
      ExamplePollService.delay.cleanup
    end
  end

  task generate_error: :environment do
    raise "this is an exception to test exception handling"
  end

  task notify_clients_of_update: :environment do
    MessageChannelService.publish_data({ version: Loomio::Version.current }, to: GlobalMessageChannel.instance)
  end

  task update_subscription_members_counts: :environment do
    SubscriptionService.update_changed_members_counts
  end
end
