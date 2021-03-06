# == Schema Information
#
# Table name: users
#
#  id                     :integer          not null, primary key
#  email                  :string(255)      default(""), not null
#  encrypted_password     :string(255)      default(""), not null
#  reset_password_token   :string(255)
#  reset_password_sent_at :datetime
#  remember_created_at    :datetime
#  sign_in_count          :integer          default(0)
#  current_sign_in_at     :datetime
#  last_sign_in_at        :datetime
#  current_sign_in_ip     :string(255)
#  last_sign_in_ip        :string(255)
#  password_salt          :string(255)
#  invitation_token       :string(255)
#  created_at             :datetime
#  updated_at             :datetime
#  approved               :boolean          default(FALSE), not null
#

class User < ActiveRecord::Base

  devise :database_authenticatable, :registerable, :recoverable, :rememberable, :trackable, :validatable, stretches: 10

  def active_for_authentication?
    if super && approved?
      true
    else
      Rails.logger.warn("[SEC] User #{email} is not approved but attempted to authenticate.")
      false
    end
  end

  def inactive_message
    if !approved?
      :not_approved
    else
      super # Use whatever other message
    end
  end

  def approve!
    update_attributes(approved: true)
    Rails.logger.info("Approved user #{email}")
  end

  def unapprove!
    update_attributes(approved: false)
    Rails.logger.info("Unapproved user #{email}")
  end

end
