# -*- encoding: utf-8 -*-

class RootsController < ApplicationController

  ############################################################################

  def show
    set_service_profile
    if authorized?
      set_user_profile
      @authorized = true
      @queued     = queued? ? true : false
    else
      set_twitter_authorize_url
      @authorized = @queued = false
    end

    respond_to do |format|
      format.html
    end
  end

  def oauth_callback
    if authentication_accepted?
      set_twitter_access_token
    end

    respond_to do |format|
      format.html { redirect_to root_url }
    end

  rescue => ex
    ExceptionNotifier::Notifier.exception_notification(request.env, ex).deliver
    flash[:notice] = 'Twitter認証に失敗しました。（◞‸◟）'

    respond_to do |format|
      format.html { redirect_to root_url }
    end

  end

  def logout
    reset_session
    respond_to do |format|
      format.html { redirect_to root_url }
    end
  end

  def notification
    raise 'メール送信テストです'
  rescue => ex
    ExceptionNotifier::Notifier.exception_notification(request.env, ex).deliver
    flash[:notice] = 'メール送信テストです'

    respond_to do |format|
      format.html { redirect_to root_url }
    end
  end

  ############################################################################

  def clean
    set_user_profile

    job = Bucket.find_by_serial(@user_profile[:twitter_id])
    if job.present?
      job.update_attributes!({
        :token  => Twitter.options[:oauth_token],
        :secret => Twitter.options[:oauth_token_secret],
      })
    else
      Bucket.create!({
        :serial => @user_profile[:twitter_id],
        :token  => Twitter.options[:oauth_token],
        :secret => Twitter.options[:oauth_token_secret],
      })
    end

    respond_to do |format|
      format.json { render :nothing => true, :status => 200 }
    end
  rescue => ex
    ExceptionNotifier::Notifier.exception_notification(request.env, ex).deliver

    respond_to do |format|
      format.json { render :nothing => true, :status => 500 }
    end
  end

  def abort
    set_user_profile

    job = Bucket.find_by_serial(@user_profile[:twitter_id])
    job.try(:destroy)

    respond_to do |format|
      format.json { render :nothing => true, :status => 200 }
    end
  rescue => ex
    ExceptionNotifier::Notifier.exception_notification(request.env, ex).deliver

    respond_to do |format|
      format.json { render :nothing => true, :status => 500 }
    end
  end

  def stats
    set_user_profile

    job = Bucket.find_by_serial(@user_profile[:twitter_id]) || (raise StandardError)
    stats = {
      :destroy_count  => job.destroy_count,
      :remaining_hits => Twitter.rate_limit_status['remaining_hits'],
      :elapsed_time   => job.elapsed_time,
      :page           => job.page
    }

    respond_to do |format|
      format.json { render :json => stats }
    end
  rescue => ex
    ExceptionNotifier::Notifier.exception_notification(request.env, ex).deliver

    respond_to do |format|
      format.json { render :nothing => true, :status => 500 }
    end
  end

  ############################################################################
  protected

  def authorized?
    session[:access_token].present?
  end

  def queued?
    session[:user_profile].present? && \
      Bucket.find_by_serial(session[:user_profile][:twitter_id]).present?
  end

  def authentication_accepted?
    (params[:oauth_token].present? && params[:oauth_verifier].present?)
  end

  ############################################################################
  protected

  def set_service_profile
    @service_profile = Stats.fetch
  end

  def set_twitter_authorize_url
    consumer = consumer_from_configatron
    request_token = consumer.get_request_token(configatron.twitter.oauth_callback)
    session[:request_token] = request_token.token
    session[:request_token_secret] = request_token.secret
    @authorize_url = request_token.authorize_url
  end

  def set_twitter_access_token
    consumer = consumer_from_configatron
    request_token = request_token_from_session

    access_token = request_token.get_access_token(
      {},
      :oauth_token => params[:oauth_token],
      :oauth_verifier => params[:oauth_verifier]
    )
    session[:access_token] = access_token.token
    session[:access_token_secret] = access_token.secret
  end

  def set_user_profile
    if session[:user_profile].blank?
      set_twitter_from_session
      session[:user_profile] = {
        :twitter_id          => Twitter.user.id,
        :twitter_screen_name => Twitter.user.screen_name
      }
    end
    @user_profile = session[:user_profile]
  end

  def set_twitter_from_session
    consumer = consumer_from_configatron
    access_token = access_token_from_session
    Twitter.configure do |config|
      config.consumer_key       = consumer.key
      config.consumer_secret    = consumer.secret
      config.oauth_token        = access_token.token
      config.oauth_token_secret = access_token.secret
    end
  end

  def access_token_from_session
    OAuth::AccessToken.new(
      consumer_from_configatron,
      session[:access_token],
      session[:access_token_secret]
    )
  end

  def request_token_from_session
    OAuth::RequestToken.new(
      consumer_from_configatron,
      session[:request_token],
      session[:request_token_secret]
    )
  end

  def consumer_from_configatron
    OAuth::Consumer.new(
      configatron.twitter.consumer_key,
      configatron.twitter.consumer_secret,
      :site => "http://twitter.com",
    )
  end
end
