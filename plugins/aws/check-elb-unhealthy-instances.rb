#!/usr/bin/env ruby
#
# Check ELB Unhealthy Instances
# =============================
#
# Check unhealthy instances by ELB API.
#
# Examples
# -----------------------------
#
#     # Warning if any load balancer's attached instance is OutOfService.
#     check-elb-unhealthy-instances --warning-over 1
#
#     # Warning if any of "app" load balancer's attached instance is OutOfService
#     # critical if 2 or more instance is OutOfService
#     check-elb-unhealthy-instances --elb-names app --warning-over 1 --critical-over 2
#
# Copyright 2014 github.com/y13i
#

require "sensu-plugin/check/cli"
require "aws-sdk"

class CheckELBLatency < Sensu::Plugin::Check::CLI
  option :access_key_id,
    short:       "-k N",
    long:        "--access-key-id ID",
    description: "AWS access key ID"

  option :secret_access_key,
    short:       "-s N",
    long:        "--secret-access-key KEY",
    description: "AWS secret access key"

  option :region,
    short:       "-r R",
    long:        "--region REGION",
    description: "AWS region"

  option :elb_names,
    short:       "-l N",
    long:        "--elb-names NAMES",
    proc:        proc {|a| a.split(/[,;]\s*/)},
    description: "Load balancer names to check. Separated by , or ;. If not specified, check all load balancers"

  %w(warning critical).each do |severity|
    option :"#{severity}_over",
      long:        "--#{severity}-over COUNT",
      proc:        proc {|a| a.to_i},
      description: "Trigger a #{severity} if unhealthy instances is specified count or over"
  end

  def aws_config
    hash = {}
    hash.update access_key_id: config[:access_key_id], secret_access_key: config[:secret_access_key] if config[:access_key_id] && config[:secret_access_key]
    hash.update region: config[:region] if config[:region]
    hash
  end

  def elb
    @elb ||= AWS::ELB.new aws_config
  end

  def elbs
    return @elbs if @elbs
    @elbs = elb.load_balancers.to_a
    @elbs.select! {|elb| config[:elb_names].include? elb.name} if config[:elb_names]
    @elbs
  end

  def flag_alert(severity, message)
    @severities[severity] = true
    @message += message
  end

  def check_unhealthy_instances(load_balancer)
    @severities.keys.each do |severity|
      threshold = config[:"#{severity}_over"]
      next unless threshold

      unhealthy_count = load_balancer.instances.health.inject 0 do |sum, health|
        sum += 1 unless health[:state] == "InService"
        sum
      end

      next if unhealthy_count < threshold
      flag_alert severity,
        "; #{elbs.size == 1 ? nil : "#{load_balancer.inspect}: "}#{unhealthy_count} unhealthy instances. (expected lower than #{threshold})"
      break
    end
  end

  def run
    @message  = if elbs.size == 1
                  elbs.first.inspect
                else
                  "#{elbs.size} load balancers total"
                end

    @severities = {
                    critical: false,
                    warning:  false,
                  }

    elbs.each {|elb| check_unhealthy_instances elb}

    if @severities[:critical]
      critical @message
    elsif @severities[:warning]
      warning @message
    else
      ok @message
    end
  end
end
