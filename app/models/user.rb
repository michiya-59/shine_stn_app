# frozen_string_literal: true

class User < ApplicationRecord
  attr_accessor :type

  has_one_attached :image
  has_one_attached :user_image
  has_secure_password
  has_many :learns, dependent: :nullify
  has_many :introduced_tmp_member_infos, foreign_key: "introducer_id", class_name: "TmpMemberInfo", dependent: :nullify, inverse_of: :introducer
  has_many :sales_tmp_member_infos, foreign_key: "sales_id", class_name: "TmpMemberInfo", dependent: :nullify, inverse_of: :sales
  has_many :child_relationships, foreign_key: "parent_id", class_name: "Relationship", dependent: :nullify, inverse_of: :parent
  has_many :children, through: :child_relationships, source: :child
  has_many :parent_relationships, foreign_key: "child_id", class_name: "Relationship", dependent: :nullify, inverse_of: :child
  has_many :rewards, dependent: :destroy
  has_many :introduced_users, class_name: "User", foreign_key: "introducer_id", dependent: :destroy, inverse_of: :introducer
  has_one :cap_adjustment_money, dependent: :destroy
  has_many :video_views, dependent: :nullify

  belongs_to :parent, class_name: "User", optional: true
  belongs_to :grade
  belongs_to :incentive, optional: true
  belongs_to :introducer, class_name: "User", optional: true, dependent: :destroy
  VALID_ALPHANUMERIC_REGEX = /\A[a-zA-Z0-9]+\z/
  VALID_EMAIL_REGEX = /\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i

  validates :login_id, uniqueness: true, format: {with: VALID_ALPHANUMERIC_REGEX, message: "は半角英数字のみで入力してください。"}
  validates :name, presence: true, length: {maximum: 30}
  validates :name_kana, presence: true
  validates :email, uniqueness: true, length: {maximum: 255}, format: {with: VALID_EMAIL_REGEX}
  validates :phone, length: {in: 10..11, message: "は10文字または11文字で入力してください。"}
  validates :birthday, presence: true
  validates :gender_id, presence: true

  class << self
    def create_user approval
      create!(
        login_id: approval&.login_id,
        email: approval&.email,
        name: approval&.name,
        name_kana: approval&.name_kana,
        birthday: approval&.birthday,
        phone: approval&.phone,
        password_digest: approval&.password_digest,
        status: 1,
        introducer_id: approval&.introducer_id,
        admin_flg: 9,
        gender_id: approval&.gender_id,
        online_flg: 9,
        grade_id: 99,
        incentive_id: approval&.incentive_id
      )
    end

    def introducer_search params, introduce_users
      if params[:name].present?
        introduce_users = introduce_users.where("name LIKE ?", "%#{params[:name]}%")
      end
      introduce_users = introduce_users.where(status: params[:status]) if params[:status].present?

      introduce_users
    end

    def calculate_rewards_for_month year, month
      start_date = Date.new(year, month, 1)
      end_date = start_date.end_of_month

      rewards.includes(:incentive)
        .where(created_at: start_date..end_date)
        .sum{|reward| reward.incentive.incentive_price}
    end
  end
end
