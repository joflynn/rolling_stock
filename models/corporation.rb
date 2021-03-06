require './models/passer'
require './models/purchaser'
require './models/ownable'

class Corporation < Purchaser
  include Passer
  include Ownable

  CORPORATIONS = %w(Android Bear Eagle Horse Jupiter Orion Saturn Ship Star Wheel).freeze

  attr_reader :name, :president, :share_price, :shares, :bank_shares, :synergy_income, :minor_version

  def self.initial_shares_info company, share_price
    value = company.value
    num_shares = (value / share_price.to_f).ceil
    seed = num_shares * share_price - value

    {
      num_shares: num_shares,
      seed: seed,
      cash: num_shares * share_price + seed,
    }
  end

  def initialize name, company, share_price, share_prices, minor_version = nil, log = nil
    super 0
    raise GameException, "Share price #{share_price.price} taken by #{share_price.corporation.name}" if share_price.corporation
    raise GameException, "Share price #{share_price.price} not valid" unless share_price.valid_range? company.tier

    @minor_version = minor_version || 0
    @name = name
    @president = company.owner
    @companies << company
    @share_price = share_price
    @share_price.corporation = self
    @share_prices = share_prices
    other_shares = (starting_shares - 1).times.map { Share.normal(self) }
    @shares = [Share.president(self)].concat other_shares
    @bank_shares = []
    @shares_count = Hash.new { |k, v| k[v] = 0 }
    @log = log || []

    company.owner.companies.delete company
    company.owner = self
    set_income

    issue_initial_shares
  end

  def id
    @name
  end

  def owner
    @president
  end

  def price
    @share_price.price
  end

  def index
    @share_price.index
  end

  def can_buy_share?
    !@bank_shares.empty?
  end

  def bankrupt?
    price.zero? || @companies.empty? || @cash < 0
  end

  def buy_share player
    raise GameException, 'Cannot buy share. None available' unless can_buy_share?
    raise GameException, 'Player does not have enough money to buy a share.' if player.cash < next_share_price.price
    swap_share_price next_share_price
    player.cash -= price
    player.shares << @bank_shares.pop
    @shares_count[player] += 1
    @log << "#{player.name} buys share of #{name} for $#{price}"
    change_president
  end

  def can_sell_share? player
    player_shares = player.corporation_shares(self)
    share = player_shares.last
    return false unless share
    !share.president? || @shares_count[player] == @shares_count.reject { |k, _| k == player }.values.max
  end

  def sell_share player
    raise GameException, 'Cannot sell share' unless can_sell_share? player
    swap_share_price prev_share_price
    player.cash += price
    share = player.corporation_shares(self).last
    share.president = false
    @bank_shares << player.shares.delete(share)
    @shares_count[player] -= 1
    @log << "#{player.name} sells share of #{name} for $#{price}"
    change_president
  end

  def change_president
    max = @shares_count.values.max
    holders = @shares_count.select { |_, count| count == max }.keys.sort_by &:order

    if !holders.include?(@president)
      @president.corporation_shares(self).each { |s| s.president = false } if @president
      player = holders.find { |p| @president && @president.order < p.order } || holders.first
      player.corporation_shares(self).first.president = true
      @president = player
      @log << "#{@president.name} becomes president of #{name}"
    end
  end

  def can_issue_share?
    @shares.size > 0
  end

  def issue_share
    raise GameException, 'Cannot issue share' unless can_issue_share?
    new_share_price = issue_share_price
    @log << "#{name} issues a share and receives $#{new_share_price.price}"
    swap_share_price new_share_price if new_share_price != @share_price
    @cash += price
    @bank_shares << @shares.shift
  end

  def issue_share_price
    prev_share_price
  end

  def set_income old_owner = nil
    super
    synergies = @companies.map { |c| [c.name, c] }.to_h
    @synergy_income = @companies.map { |company| company.synergy_income synergies }.reduce(&:+)
    @income += @synergy_income
  end

  def pay_dividend amount, players
    raise GameException, 'Dividend must be positive' if amount < 0
    raise GameException, 'Total dividends must be payable with corporation cash and must not exceed 1/3 share price per share' if amount > max_dividend

    @cash -= amount * @bank_shares.size

    dividend_log = String.new "#{name} pays $#{amount} dividends"

    players.each do |player|
      total = amount * player.shares.count { |share| share.corporation == self }
      @cash -= total
      player.cash += total
      dividend_log << " - #{player.name} receives $#{total}" if total > 0
    end
    @log << dividend_log

    adjust_share_price
  end

  def max_dividend
    [@share_price.max_dividend, @cash / shares_issued].min
  end

  def book_value
    @cash + @pending_cash + @companies.reduce(0) { |p, c| c.value + p }
  end

  def market_cap
    shares_issued * price
  end

  def shares_issued
    starting_shares - @shares.size
  end

  def prev_share_price interval = 1
    return nil if index == 0
    return @share_prices[0] if index - interval <= 0
    @share_prices.slice(0..(index - interval)).reverse.find &:unowned?
  end

  def next_share_price interval = 1
    return nil if index >= @share_prices.size - 1
    max = index + interval
    max = @share_prices.size - 1 if max >= @share_prices.size
    @share_prices.slice(max..-1).find &:unowned?
  end

  def image_url
    "/images/#{name.downcase}-20.png"
  end

  def type
    'corporation'
  end

  private
  def starting_shares
    10
  end

  def issue_initial_shares
    company = @companies.first
    info = self.class.initial_shares_info company, price
    seed = info[:seed]
    num_shares = info[:num_shares]
    cash = info[:cash]

    raise GameException, "You don't have enough money to form at that share price" if @president.cash < seed

    @president.cash -= seed
    @cash = cash

    @president.shares.concat @shares.shift(num_shares)
    @shares_count[@president] += num_shares
    @bank_shares.concat @shares.shift(num_shares)
    @log << "#{owner.name} forms corporation #{name} with #{company.name} at $#{price} - #{num_shares * 2} shares issued."
  end

  def swap_share_price new_price
    return unless new_price
    @log << "#{name} changes share price from $#{price} to $#{new_price.price}"
    new_price.corporation = self
    @share_price.corporation = nil
    @share_price = new_price
  end

  def above_valuation?
    book_value - market_cap >= 0
  end

  def adjust_share_price
    old_index = index

    if above_valuation?
      swap_share_price next_share_price

      if (index - old_index == 1) && above_valuation?
        swap_share_price next_share_price
      end
    else
      swap_share_price prev_share_price

      if (old_index - index == 1) && !above_valuation?
        swap_share_price prev_share_price
      end
    end
  end
end
