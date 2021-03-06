require 'csv'

class SearchController < ApplicationController

  include PeopleHelper
  include GsmHelper

  # FIXME: Refactor and re-enable cop
  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  #
  def index
    # no pagination for CSV export
    per_page = request.format.to_s.eql?('text/csv') ? 10000 : Person.per_page

    @results = if params[:q]
                 Person.search params[:q], per_page: per_page, page: (params[:page] || 1)
               elsif params[:adv]
                 Person.complex_search(params, per_page) # FIXME: more elegant solution for returning all records
               else
                 []
               end

    respond_to do |format|
      format.html {}
      format.csv do
        fields = Person.column_names
        fields.push("tags")
        output = CSV.generate do |csv|
          # Generate the headers
          csv << fields.map(&:titleize)

          # Some fields need a helper method
          human_devices = %w( primary_device_id secondary_device_id )
          human_connections = %w( primary_connection_id secondary_connection_id )

          # Write the results
          @results.each do |person|
            csv << fields.map do |f|
              field_value = person[f]
              if human_devices.include? f
                human_device_type_name(field_value)
              elsif human_connections.include? f
                human_connection_type_name(field_value)
              elsif f == "tags"
                if person.tag_values.blank?
                  ""
                else
                  person.tag_values.join('|')
                end
              else
                field_value
              end
            end
          end
        end
        send_data output
      end
    end
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  # FIXME: Refactor and re-enable cop
  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
  #
  def export
    # send all results to a new static segment in mailchimp
    list_name = params.delete(:name)
    @people = Person.complex_search(params, 10000)
    @mce = MailchimpExport.new(name: list_name, recipients: @people.collect(&:email_address), created_by: current_user.id)

    if @mce.with_user(current_user).save
      Rails.logger.info("[SearchController#export] Sent #{@mce.recipients.size} email addresses to a static segment named #{@mce.name}")
      respond_to do |format|
        format.js {}
      end
    else
      Rails.logger.error("[SearchController#export] failed to send event to mailchimp: #{@mce.errors.inspect}")
      format.all { render text: "failed to send event to mailchimp: #{@mce.errors.inspect}", status: 400 }
    end
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

  # FIXME: Refactor and re-enable cop
  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Style/MethodName, Style/VariableName
  #
  def exportTwilio
    # send messages to all people
    message1 = params.delete(:message1)
    message2 = params.delete(:message2)
    message1 = to_gsm0338(message1)
    message2 = to_gsm0338(message2) if message2.present?
    messages = Array[message1, message2]
    smsCampaign = params.delete(:twiliowufoo_campaign)
    @people = Person.complex_search(params, 10000)
    # people_count = @people.length
    Rails.logger.info("[SearchController#exportTwilio] people #{@people}")
    phone_numbers = @people.collect(&:phone_number)
    Rails.logger.info("[SearchController#exportTwilio] people #{phone_numbers}")
    phone_numbers = phone_numbers.reject { |e| e.to_s.blank? }
    @job_enqueue = Delayed::Job.enqueue SendTwilioMessagesJob.new(messages, phone_numbers, smsCampaign)
    if @job_enqueue.save
      Rails.logger.info("[SearchController#exportTwilio] Sent #{phone_numbers} to Twilio")
      respond_to do |format|
        format.js {}
      end
    else
      Rails.logger.error('[SearchController#exportTwilio] failed to send text messages')
      format.all { render text: 'failed to send text messages', status: 400 }
    end
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Style/MethodName, Style/VariableName

end
