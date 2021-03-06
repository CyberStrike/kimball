# FIXME: Refactor and re-enable cop
# rubocop:disable ClassLength
class PeopleController < ApplicationController

  before_action :set_person, only: [:show, :edit, :update, :destroy]

  skip_before_action :authenticate_user!, if: :should_skip_janky_auth?
  skip_before_action :verify_authenticity_token, only: [:create, :create_sms]

  # GET /people
  # GET /people.json
  def index
    @people = Person.paginate(page: params[:page]).order('signup_at DESC')
  end

  # GET /people/1
  # GET /people/1.json
  def show
    @comment = Comment.new commentable: @person
    @reservation = Reservation.new person: @person
    @tagging = Tagging.new taggable: @person
    @outgoingmessages = TwilioMessage.where(to: @person.normalized_phone_number).where.not(wufoo_formid: nil)
    @outgoingmessages = @outgoingmessages.to_a.uniq { |p| p.wufoo_formid }
  end

  # GET /people/new
  def new
    @person = Person.new
  end

  # GET /people/1/edit
  def edit
  end

  # FIXME: Refactor and re-enable cop
  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/AbcSize,  Metrics/MethodLength, Rails/TimeZone
  #
  # POST /people/create_sms
  def create_sms
    if params['HandshakeKey'].present?
      if Logan::Application.config.wufoo_handshake_key != params['HandshakeKey']
        Rails.logger.warn("[wufoo] received request with invalid handshake. Full request: #{request.inspect}")
        head(403) && return
      end
      render nothing: true
      Rails.logger.info('[wufoo] received a submission from wufoo')
      # @person = Person.initialize_from_wufoo_sms(params)
      new_person = Person.new

      # Save to Person
      new_person.first_name = params['Field275'].strip
      new_person.last_name = params['Field276'].strip
      new_person.address_1 = params['Field268'].strip
      new_person.postal_code = params['Field271'].strip
      new_person.phone_number = params['Field281'].strip

      if params['Field279'].strip.upcase != 'SKIP'
        new_person.email_address = params['Field279'].strip
      end
      # new_person.save
      new_person.primary_device_id = case params['Field39'].upcase.strip
                                     when 'A'
                                       Person.map_device_to_id('Desktop computer')
                                     when 'B'
                                       Person.map_device_to_id('Laptop')
                                     when 'C'
                                       Person.map_device_to_id('Tablet')
                                     when 'D'
                                       Person.map_device_to_id('Smart phone')
                                     else
                                       params['Field39']
                                     end

      new_person.primary_device_description = params['Field21'].strip

      new_person.primary_connection_id = case params['Field41'].upcase.strip
                                         when 'A'
                                           Person.map_connection_to_id('Broadband at home')
                                         when 'B'
                                           Person.map_connection_to_id('Phone plan with data')
                                         when 'C'
                                           Person.map_connection_to_id('Public wi-fi')
                                         when 'D'
                                           Person.map_connection_to_id('Public computer center')
                                         else
                                           params['Field41']
                                         end

      new_person.preferred_contact_method = if params['Field278'].upcase.strip == 'TEXT'
                                              'SMS'
                                            else
                                              'EMAIL'
                                            end

      new_person.verified = 'Verified by Text Message Signup'
      new_person.signup_at = Time.now

      new_person.save
    end
  end
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/AbcSize,  Metrics/MethodLength, Rails/TimeZone

  # FIXME: Refactor and re-enable cop
  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  #
  # POST /people
  # POST /people.json
  def create
    from_wufoo = false
    # if uatest == "Wufoo.com"
    if params['HandshakeKey'].present?
      if Logan::Application.config.wufoo_handshake_key != params['HandshakeKey']
        Rails.logger.warn("[wufoo] received request with invalid handshake. Full request: #{request.inspect}")
        head(403) && return
      end

      Rails.logger.info('[wufoo] received a submission from wufoo')
      from_wufoo = true
      @person = Person.initialize_from_wufoo(params)
      @person.save
      begin
        @client = Twilio::REST::Client.new(ENV['TWILIO_ACCOUNT_SID'], ENV['TWILIO_AUTH_TOKEN'])
        @twilio_message = TwilioMessage.new
        @twilio_message.from = ENV['TWILIO_SIGNUP_VERIFICATION_NUMBER']
        @twilio_message.to = @person.normalized_phone_number
        @twilio_message.body = "Thank you for signing up for the CUTGroup! Please text us 'Hello' or 12345 to complete your signup. If you did not sign up, text 'Remove Me' to be removed."

        @twilio_message.signup_verify = 'Yes'
        @twilio_message.save
        @message = @client.messages.create(
          from: ENV['TWILIO_SIGNUP_VERIFICATION_NUMBER'],
          to: @person.normalized_phone_number,
          body: @twilio_message.body
        # status_callback: request.base_url + "/twilio_messages/#{@twilio_message.id}/updatestatus"
        )
        @twilio_message.message_sid = @message.sid
      rescue Twilio::REST::RequestError => e
        error_message = e.message
        @twilio_message.error_message = error_message
        Rails.logger.warn("[Twilio] had a problem. Full error: #{error_message}")
        @person.verified = error_message
        @person.save
      end

      @twilio_message.account_sid = ENV['TWILIO_ACCOUNT_SID']
      # @twilio_message.error_nessage
      @twilio_message.save

    # end
    else
      # creating a person by hand
      @person = Person.new(person_params)
    end

    respond_to do |format|
      if @person.save

        from_wufoo ? format.html { head :created } : format.html { redirect_to @person, notice: 'Person was successfully created.' }
        format.json { render action: 'show', status: :created, location: @person }
      else
        format.html { render action: 'new' }
        format.json { render json: @person.errors, status: :unprocessable_entity }
      end
    end
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  # PATCH/PUT /people/1
  # PATCH/PUT /people/1.json
  def update
    respond_to do |format|
      if @person.with_user(current_user).update(person_params)
        format.html { redirect_to @person, notice: 'Person was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render action: 'edit' }
        format.json { render json: @person.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /people/1
  # DELETE /people/1.json
  def destroy
    @person.destroy
    respond_to do |format|
      format.html { redirect_to people_url }
      format.json { head :no_content }
    end
  end

  private

    # Use callbacks to share common setup or constraints between actions.
    def set_person
      @person = Person.find(params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def person_params
      params.require(:person).permit(:first_name, :last_name, :verified, :email_address, :address_1, :address_2, :city, :state, :postal_code, :geography_id, :primary_device_id, :primary_device_description, :secondary_device_id, :secondary_device_description, :primary_connection_id, :primary_connection_description, :secondary_connection_id, :secondary_connection_description, :phone_number, :participation_type, :preferred_contact_method)
    end

    def should_skip_janky_auth?
      # don't attempt authentication on reqs from wufoo
      (params[:action] == 'create' || params[:action] == 'create_sms') && params['HandshakeKey'].present?
      # params[:action] == 'create_sms' && params['HandshakeKey'].present?
    end

end
# rubocop:enable ClassLength
