# -*- encoding: utf-8 -*-

class Mention
  @queue = :tweet_bot

  def self.perform
    search_and_destroy('ツイート 全消し OR 全削除')
    search_and_destroy('ツイート 全部 OR 全て 消したい OR 削除 OR 消す')
    nil
  end

  def self.search_and_destroy(conditions)
    prtool = Prtool.find_or_create_by_context(:mention_destroy)
    prtool.users ||= Hash.new
    begin
      tweets = Hash.new
      twitter = twitter_client
      twitter.search(conditions).each do |tweet|
        next if prtool.users.has_key?(tweet.from_user_id)
        twitter.update(
          "#{tweet.from_user} #{chuni_reply}",
          { :in_reply_to_status_id => tweet.id, :trim_user => true }
        )
        tweets[tweet.from_user_id] = tweet.id
      end
    ensure
      prtool.update_attributes!({
        :context => :mention_destroy,
        :users   => prtool.users.merge(tweets)
      })
      if !tweets.empty?
        twitter.update('黒歴史クリーナーのアドレスはこちらです(´・ω・`) - http://kurorekishi.yabasoft.biz/')
      else
        twitter.update(chuni_tweet) if rand(3) == 0
      end
    end
    nil
  end

  def self.chuni_reply
    replies = lambda {
      lines = open("#{Rails.root}/db/chuni_t.txt").read
      lines.chomp.split("\n")
    }.call
    replies[rand(replies.length)]
  end

  def self.chuni_tweet
    tweets = lambda {
      lines = open("#{Rails.root}/db/chuni.txt").read
      lines.chomp.split("\n")
    }.call
    tweets[rand(tweets.length)]
  end

  def self.twitter_client
    Twitter.configure do |config|
      config.consumer_key       = configatron.prtools.twitter.customer_key
      config.consumer_secret    = configatron.prtools.twitter.consumer_secret
      config.oauth_token        = configatron.prtools.twitter.access_token
      config.oauth_token_secret = configatron.prtools.twitter.access_token_secret
    end
    Twitter.new
  end

end
