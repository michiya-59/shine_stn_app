# frozen_string_literal: true

# rubocop:disable Metrics/AbcSize
# rubocop:disable Metrics/MethodLength
# rubocop:disable Metrics/BlockLength

class RewardsController < ApplicationController
  before_action :reward_load_data
  before_action :set_date

  def index
    # 管理者が各会員の報酬詳細を確認する際に、ユーザのIDで検索した際に、渡ってくる会員ID
    if params[:id].present?
      session[:reward_only_user_id] = params[:id]
      @target_user = User.find(params[:id])
    end

    totle_payment_price = get_totle_payment_price
    @certificate_of_tax_deducted_price, fee_price = calculate_y(totle_payment_price)
    @cap_adjustment_money = CapAdjustmentMoney.find_by(user_id: params[:id])&.price
    @total_payment_price = totle_payment_price - @certificate_of_tax_deducted_price - fee_price - @cap_adjustment_money.to_i
  end

  def user_list
    @user_all = User.select(:id, :name).all

    if params[:id].present?
      @user = User.select(:id, :name).find(params[:id])
    else
      @users = @user_all
    end
  end

  def pdf_output
    # ボーナス合計
    total_price = get_totle_payment_price
    certificate_of_tax_deducted_price, fee_price = calculate_y(total_price)
    # キャップ調整金
    cap_adjustment_money = CapAdjustmentMoney.find_by(user_id: params[:id])&.price
    # 総支払額
    total_payment_price = total_price - certificate_of_tax_deducted_price - fee_price - cap_adjustment_money.to_i
    # 源泉徴収
    tax_withholding = return_deduction_price total_payment_price, certificate_of_tax_deducted_price
    user = User.find(params[:id])
    reward_info = {
      # ボーナス月日
      reward_month: "#{@search_year}年#{@search_month}月",
      # ユーザ情報
      user:,
      # 直商会ボーナス
      reward_bonus_total: @reward_bonus_total,
      # ２ティアボーナス
      two_tier_bonus_total: @two_tier_bonus_total,
      # タイトルボーナス
      title_bonus_total: @title_bonus_total,
      # aさんボーナス
      a_san_bonus_total: @a_san_bonus_total,
      # 源泉徴収
      tax_withholding:,
      # 事務手数料
      administration_fee: "-500",
      # キャップ調整金
      cap_adjustment_money:,
      # ボーナス合計
      total_price:,
      # 総支払額
      total_payment_price:
    }

    respond_to do |format|
      format.html
      format.pdf do
        pdf = create_pdf reward_info
        send_data pdf.render, filename: "給与明細_#{Time.zone.now.strftime('%Y%m%d')}.pdf",
                              type: "application/pdf",
                              disposition: "inline"
      end
    end
  end

  private

  def create_pdf reward_info
    Prawn::Document.new(page_size: "A4") do |pdf|
      # フォント設定
      pdf.font_families.update("IPAex" => {
                                 normal: "app/assets/fonts/ipaexm.ttf",
                                 bold: "app/assets/fonts/ipaexg.ttf"
                               })
      pdf.font "IPAex"

      # 会社情報
      pdf.text "株式会社Shine", align: :right, size: 14
      pdf.move_down 9
      pdf.text "〒160-0023", align: :right, size: 14
      pdf.move_down 2
      pdf.text "東京都新宿区西新宿三丁目3番13号", align: :right, size: 14
      pdf.move_down 2
      pdf.text "西新宿水間ビル2F", align: :right, size: 14
      pdf.move_down 38

      # タイトル
      title = "ボーナス明細書"
      title_options = {size: 20, style: :bold, align: :center}
      title_width = pdf.width_of(title, title_options)
      title_height = 40 # 背景の高さ

      # テキストの位置を決定
      pdf.bounding_box([0, pdf.cursor], width: pdf.bounds.width, height: title_height) do
        # 背景色を描画
        pdf.fill_color "FFF4E5"
        pdf.fill_rectangle([pdf.bounds.left, pdf.bounds.top], pdf.bounds.width, title_height)

        # テキストを描画
        text_x = (pdf.bounds.width - title_width) / 2
        pdf.move_down 9 # テキストの位置を調整
        pdf.fill_color "000000"
        pdf.text title, title_options

        # テキストの下に下線を描画
        line_y = pdf.cursor - 3 # 下線の位置を調整
        pdf.stroke_color "000000"
        pdf.line_width 1
        pdf.stroke_line [text_x, line_y], [text_x + title_width, line_y]
      end
      pdf.move_down 6
      pdf.text (reward_info[:reward_month]).to_s, align: :center, size: 12
      pdf.move_down 20

      # 会員IDと氏名のテーブル
      member_info_data = [
        ["会員ID", reward_info[:user]&.id.to_s, "", "氏名", reward_info[:user]&.name.to_s]
      ]
      pdf.table(member_info_data, width: pdf.bounds.width) do
        cells.padding = [10, 10]
        cells.align = :center
        cells.borders = %i(top bottom left right)
        # 太枠線の設定
        cells.border_width = 2
        # 文字サイズの設定
        cells.size = 16
        cells.font_style = :bold
        # 空白セルの設定
        column(2).width = 0
        column(2).borders = []
      end
      pdf.move_down 40

      total_payment_price = reward_info[:total_payment_price].to_i < 0 ? 0 : reward_info[:total_payment_price]
      # 振込額のテーブル
      transfer_amount_data = [
        ["振込額", "¥ #{total_payment_price}"]
      ]

      pdf.table(transfer_amount_data, width: pdf.bounds.width) do
        cells.padding = [10, 50]
        cells.borders = %i(top bottom left right)
        cells.border_width = 2
        cells.size = 16
        cells.font_style = :bold
        cells.background_color = "fff4e5"

        columns(0).align = :left
        columns(1).align = :right

        columns(0).borders = %i(top bottom left)
        columns(1).borders = %i(top bottom right)
      end

      pdf.move_down 40

      # テーブルの幅を計算（ページの幅の半分）
      half_width = pdf.bounds.width / 2.1
      cap_cap_adjustment_money = reward_info[:cap_adjustment_money].present? ? "-#{reward_info[:cap_adjustment_money]}" : 0
      cap_money = (reward_info[:cap_adjustment_money].presence || 0)
      now_month_bonus = reward_info[:total_price].to_i - cap_money.to_i

      free_pay = reward_info[:total_payment_price] > 500 ? -500 : 0
      # 左側のテーブル（ボーナス詳細）
      left_table_data = [
        ["ボーナス合計額", "¥ #{reward_info[:total_price]}"],
        ["", ""],
        ["CAP調整金", "¥ #{cap_cap_adjustment_money}"],
        ["調整金", "¥0"],
        ["過不足金", "¥0"],
        ["繰越金", "¥0"],
        ["当月ボーナス取得額合計", "¥ #{now_month_bonus}"],
        ["", ""],
        ["", ""],
        ["源泉所得税", "¥ #{reward_info[:tax_withholding]}"],
        ["振込事務手数料", "¥ #{free_pay}"],
        ["振込額", "¥ #{reward_info[:total_payment_price]}"]
      ]

      #  左側のテーブルを描画
      pdf.table(left_table_data, position: :left, width: half_width) do
        cells.border_bottom_width = 1
        cells.border_bottom_color = "000000"
        cells.valign = :center

        row(0..11).height = 22
        12.times do |row_index|
          row(row_index).columns(1).align = :right
        end

        match_data = left_table_data[2][1].match(/-?\d+/)
        cells[2, 1].text_color = "FF0000" if match_data[0].to_i < 0

        match_data = left_table_data[6][1].match(/-?\d+/)
        cells[6, 1].text_color = "FF0000" if match_data[0].to_i < 0

        match_data = left_table_data[9][1].match(/-?\d+/)
        cells[9, 1].text_color = "FF0000" if match_data[0].to_i < 0

        match_data = left_table_data[10][1].match(/-?\d+/)
        cells[10, 1].text_color = "FF0000" if match_data[0].to_i < 0

        match_data = left_table_data[11][1].match(/-?\d+/)
        cells[11, 1].text_color = "FF0000" if match_data[0].to_i < 0
        row(0..5).borders = [:bottom]
        # row(6)の操作
        cells[6, 0].borders = %i(top bottom left)
        cells[6, 0].border_width = 2
        cells[6, 1].borders = %i(top bottom right)
        cells[6, 1].border_width = 2
        row(6).border_width = 2
        row(7..10).borders = [:bottom]
        # row(11)の操作
        cells[11, 0].borders = %i(top bottom left)
        cells[11, 0].border_width = 2
        cells[11, 1].borders = %i(top bottom right)
        cells[11, 1].border_width = 2
      end

      # 右側のテーブル（ボーナス内訳）
      right_table_data = [
        ["【ボーナス内訳】", ""],
        ["リクルートボーナス", "¥ #{reward_info[:reward_bonus_total]}"],
        ["2ティアボーナス", "¥ #{reward_info[:two_tier_bonus_total]}"],
        ["Aさんボーナス", "¥ #{reward_info[:a_san_bonus_total]}"],
        ["タイトルボーナス", "¥ #{reward_info[:title_bonus_total]}"],
        ["", ""],
        ["", ""],
        ["", ""],
        ["", ""],
        ["", ""],
        ["ボーナス合計額", "¥ #{reward_info[:total_price]}"]
      ]

      cell_height = 22
      # 右側のテーブルを描画するためにカーソルを上に移動
      pdf.move_up(left_table_data.length * cell_height) # 20は各行の高さ

      # 右側のテーブルを描画
      pdf.table(right_table_data, position: :right, width: half_width) do
        cells.valign = :center
        row(0..10).height = 22
        row(0..10).borders = [:bottom]
        row(0..10).border_width = 1
        11.times do |row_index|
          row(row_index).columns(1).align = :right
        end
        row(0).font_style = :bold
        row(0).padding = [0, 0, 8, 0]

        cells[10, 0].borders = %i(top bottom left)
        cells[10, 0].border_width = 2
        cells[10, 1].borders = %i(top bottom right)
        cells[10, 1].border_width = 2
        row(10).border_width = 2
      end

      pdf.move_down 50

      remarks = ""
      # 備考欄の追加
      pdf.text "■備考", size: 12, style: :bold
      pdf.move_down 10
      # 備考欄のテキストエリア
      pdf.bounding_box([pdf.bounds.left, pdf.cursor], width: pdf.bounds.width, height: 100) do
        pdf.stroke_bounds # 枠線を描画
        pdf.text remarks, valign: :top
      end
    end
  end

  def reward_load_data
    session[:search_rewards_year] = params[:search_year] if params[:search_year].present?
    session[:search_rewards_month] = params[:search_month] if params[:search_month].present?
  end

  def get_totle_payment_price
    reward_bonus_incentive_ids = [1, 2]
    two_tier_bonus_incentive_ids = [3, 4]
    a_san_bonus_incentive_ids = [5, 6]
    title_bonus_incentive_ids = [7, 8]

    user_id = (session[:reward_only_user_id].presence || current_user.id)
    if session[:search_rewards_year].present? && session[:search_rewards_month].present?
      @reward_bonus_total = calculate_monthly_user_rewards(user_id, *reward_bonus_incentive_ids, session[:search_rewards_year].to_i, session[:search_rewards_month].to_i)
      @two_tier_bonus_total = calculate_monthly_user_rewards(user_id, *two_tier_bonus_incentive_ids, session[:search_rewards_year].to_i, session[:search_rewards_month].to_i)
      @a_san_bonus_total = calculate_monthly_user_rewards(user_id, *a_san_bonus_incentive_ids, session[:search_rewards_year].to_i, session[:search_rewards_month].to_i)
      @title_bonus_total = calculate_monthly_user_rewards(user_id, *title_bonus_incentive_ids, session[:search_rewards_year].to_i, session[:search_rewards_month].to_i)
    else
      @reward_bonus_total = calculate_monthly_user_rewards(user_id, *reward_bonus_incentive_ids, nil, nil)
      @two_tier_bonus_total = calculate_monthly_user_rewards(user_id, *two_tier_bonus_incentive_ids, nil, nil)
      @a_san_bonus_total = calculate_monthly_user_rewards(user_id, *a_san_bonus_incentive_ids, nil, nil)
      @title_bonus_total = calculate_monthly_user_rewards(user_id, *title_bonus_incentive_ids, nil, nil)
    end

    @reward_bonus_total + @two_tier_bonus_total + @a_san_bonus_total + @title_bonus_total
  end

  def set_date
    @search_year, @search_month = set_search_date params, session[:search_rewards_year], session[:search_rewards_month]
  end

  # 特定のユーザーとincentive_idセットの現在の月の合計報酬額を算出
  def calculate_monthly_user_rewards(user_id, *incentive_ids, year, month)
    if year.present? && month.present?
      # 引数で指定された年月を使う
      start_date = Date.new(year, month, 1)
      end_date = start_date.end_of_month
    else
      # 引数が指定されていない場合、現在の月を使う
      start_date = Date.current.beginning_of_month
      end_date = Date.current.end_of_month
    end

    # Rewardモデルから、関連するレコードを検索
    rewards = Reward.where(user_id:, incentive_id: incentive_ids, created_at: start_date..end_date)

    # Incentiveモデルと結合して、incentive_priceの合計を計算
    incentives_total = rewards.joins(:incentive).sum("incentives.incentive_price")

    # Rewardモデルのincentive_priceの合計を計算
    rewards_total = rewards.sum{|reward| reward.incentive_price || 0}

    # 両方の合計を足し合わせる
    @total = incentives_total + rewards_total
  end

  def calculate_y totle_price
    certificate_of_tax_deducted_price = if totle_price > 120_000
                                          (totle_price - 120_000) * 0.1021
                                        else
                                          0
                                        end

    fee_price = if totle_price > 500
                  500
                else
                  0
                end

    [certificate_of_tax_deducted_price.to_i, fee_price.to_i]
  end
end

# rubocop:enable Metrics/AbcSize
# rubocop:enable Metrics/MethodLength
# rubocop:enable Metrics/BlockLength
