require "bundler/setup"
require 'sinatra/base'
require "sinatra/reloader"
require "sinatra/config_file"
require "sinatra/json"
require 'redis'
require 'active_support'
require 'active_support/core_ext'

class App < Sinatra::Base
  configure :development do
    register Sinatra::Reloader
  end

  register Sinatra::ConfigFile
  config_file 'settings.yml'

  helpers do
    def redis
      @redis ||= Redis.new(url: settings.redis_url)
    end

    def last_block
      redis.get('processed-block-number') || 0
    end

    def get_amount(name)
      key = settings.contract_addresses[name]
      (redis.get("#{key}-amount") || 0).to_f
    end

    def yes_votes
      @yes_votes ||= {
        "0 ≤ reward < 1.5" => get_amount(:yes_contract_1),
        "1.5 ≤ reward < 2" => get_amount(:yes_contract_2),
        "2 ≤ reward < 3"   => get_amount(:yes_contract_3),
        "3 ≤ reward < 4"   => get_amount(:yes_contract_4),
        "reward ≥ 4"       => get_amount(:yes_contract_5)
      }
    end

    def yes_vote_amount
      @yes_vote_amount ||= yes_votes.values.sum.round(4)
    end

    def no_vote_amount
      @no_vote_amount ||= get_amount(:no_contract).round(4)
    end

    def precentage(n, base)
      return 0.0 if base.zero?

      (n.to_f / base.to_f * 100).round(4)
    end

    def total_amount
      @total_amount ||= yes_vote_amount + no_vote_amount
    end

    def yes_precentage
      precentage(yes_vote_amount, total_amount)
    end

    def no_precentage
      precentage(no_vote_amount, total_amount)
    end
  end

  get '/' do
    erb :index, locals: {
      settings: settings,
      last_block: last_block,
      no_vote_amount: no_vote_amount,
      yes_vote_amount: yes_vote_amount
    }
  end

  get '/vote' do
    yes_drilldown = yes_votes.reduce([]) do |sum, i|
      sum << [CGI.escape_html(i[0]), i[1], precentage(i[1], yes_vote_amount)]
    end

    json({
      yes_precentage: yes_precentage,
      yes_drilldown: yes_drilldown,
      no_vote_amount: no_vote_amount,
      no_precentage: no_precentage
    })
  end
end
