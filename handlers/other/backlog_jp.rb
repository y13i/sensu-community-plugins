#!/usr/bin/env ruby
#
# Sensu Handler: backlog_jp
#
# This handler formats alerts as mails and sends them off to a pre-defined recipient.
# Copyright 2014 github.com/y13i
#
# Requires backlog_jp gem `gem install backlog_jp`
#
# Released under the same terms as Sensu (the MIT license); see LICENSE
# for details.

require 'rubygems' if RUBY_VERSION < '1.9.0'
require "sensu-handler"
require "backlog_jp"

class BacklogJpHandler < Sensu::Handler
  def backlog_settings
    settings["handlers"]["backlog_jp"]
  end

  def configure
    BacklogJp.configure do |config|
      config.space    = backlog_settings["space"]
      config.username = backlog_settings["username"]
      config.password = backlog_settings["password"]
    end
  end

  def status
    case @event['check']['status']
    when 0 then "OK"
    when 1 then "Warning"
    when 2 then "Critical"
    when 3 then "Unknown"
    end
  end

  def short_name
    @event['client']['name'] + '/' + @event['check']['name']
  end

  def action
   @event['action'].eql?('resolve') ? "RESOLVED" : "ALERT"
  end

  def subject
    "#{action}::#{status.upcase} - #{short_name}: #{@event['check']['notification']}"
  end

  def body
    <<-EOS
#{@event['check']['output']}
Host: #{@event['client']['name']}
Timestamp: #{Time.at(@event['check']['issued'])}
Address: #{@event['client']['address']}
Check Name: #{@event['check']['name']}
Command: #{@event['check']['command']}
Status: #{status}
Occurrences: #{@event['occurrences']}
History: #{@event['check']['history']}

AWS Account: #{@event["client"]["aws_account_name"]}
adminpack: #{@event["client"]["adminpack_url"]}
Backlog Wiki: #{@event["client"]["backlog_wiki_url"]}
Backlog Project: #{@event["client"]["backlog_project_url"]}
Instance ID: #{@event["client"]["ec2_instance_id"]}
Instance Type: #{@event["client"]["ec2_instance_type"]}
Availability Zone: #{@event["client"]["ec2_availability_zone"]}

Customer Name: #{@event["client"]["customer_name"]}
Customer Description:
#{@event["client"]["customer_description"]}

Project Name: #{@event["client"]["project_name"]}
Project Description:
#{@event["client"]["project_description"]}
    EOS
  end

  def handle
    configure
    project = BacklogJp::Project[backlog_settings["project_key"]]

    BacklogJp.client.create_issue(
      projectId:   project.id,
      summary:     subject,
      description: body,
    )
  rescue
    puts 'backlog_jp -- error while attempting to ' + @event['action'] + ' an incident -- ' + short_name
  end
end
