class AlliesController < ApplicationController
  before_filter :if_not_signed_in

  # GET /allies
  # GET /allies.json
  def index
    @page_search = true
    @accepted_allies = current_user.allies_by_status(:accepted)
    @incoming_ally_requests = current_user.allies_by_status(:pending_from_user)
    @outgoing_ally_requests = current_user.allies_by_status(:pending_from_ally)
    @page_title = "Allies"
  end

  def add
    allyship = Allyship.find_by(user_id: current_user.id, ally_id: params[:ally_id])

    if allyship
      allyship.update(status: User::ALLY_STATUS[:accepted])

      # Notify the user who made the request
      pusher_type = 'accepted_ally_request'

      # Get rid of original new_ally_request notification
      uniqueid = 'new_ally_request_' + params[:ally_id].to_s
      Notification.find_by(userid: current_user.id, uniqueid: uniqueid).destroy if !Notification.find_by(userid: current_user.id, uniqueid: uniqueid).nil?
    else
      Allyship.create(
        user_id: current_user.id,
        ally_id: params[:ally_id],
        status: User::ALLY_STATUS[:pending_from_ally]
      )

      # Notify the user the request has been made to
      pusher_type = 'new_ally_request'
    end

    user = User.where(id: current_user.id).first.name
    uniqueid = pusher_type.to_s + '_' + current_user.id.to_s

    data = JSON.generate({
      user: user,
      userid: current_user.id,
      type: pusher_type,
      uniqueid: uniqueid
      })

    Notification.create(userid: params[:ally_id], uniqueid: uniqueid, data: data)
    notifications = Notification.where(userid: params[:ally_id]).order("created_at ASC").all
    Pusher['private-' + params[:ally_id]].trigger('new_notification', {notifications: notifications})
    
    NotificationMailer.notification_email(params[:ally_id], data).deliver

    respond_to do |format|
      format.html { redirect_to params[:refresh] }
      format.json { head :no_content }
    end
  end

  def remove
    # Remove original ally request notifications
    # Case 1: user terminating allyship did not initiate allyship
    uniqueid = 'new_ally_request_' + params[:ally_id].to_s
    Notification.find_by(userid: current_user.id, uniqueid: uniqueid).destroy if !Notification.find_by(userid: current_user.id, uniqueid: uniqueid).nil?
    uniqueid = 'accepted_ally_request_' + current_user.id.to_s
    Notification.find_by(userid: params[:ally_id], uniqueid: uniqueid).destroy if !Notification.find_by(userid: params[:ally_id], uniqueid: uniqueid).nil?

    # Case 2: user terminating allyship did initiate allyship
    uniqueid = 'new_ally_request_' + current_user.id.to_s
    Notification.find_by(userid: params[:ally_id], uniqueid: uniqueid).destroy if !Notification.find_by(userid: params[:ally_id], uniqueid: uniqueid).nil?
    uniqueid = 'accepted_ally_request_' + params[:ally_id].to_s
    Notification.find_by(userid: current_user.id, uniqueid: uniqueid).destroy if !Notification.find_by(userid: current_user.id, uniqueid: uniqueid).nil?

    # Remove ally from all viewers lists
    Moment.where(userid: current_user.id.to_i).all.each do |moment|
      viewers = moment.viewers
      if viewers.include? params[:ally_id].to_i
        viewers.delete(params[:ally_id].to_i)
        Moment.update(moment.id, viewers: viewers)
      end
    end

    Moment.where(userid: params[:ally_id].to_i).all.each do |moment|
      viewers = moment.viewers
      if viewers.include? current_user.id.to_i
        viewers.delete(current_user.id.to_i)
        Moment.update(moment.id, viewers: viewers)
      end
    end

    Strategy.where(userid: current_user.id.to_i).all.each do |strategy|
      viewers = strategy.viewers
      if viewers.include? params[:ally_id].to_i
        viewers.delete(params[:ally_id].to_i)
        Strategy.update(moment.id, viewers: viewers)
      end
    end

    Strategy.where(userid: params[:ally_id].to_i).all.each do |strategy|
      viewers = strategy.viewers
      if viewers.include? current_user.id.to_i
        viewers.delete(current_user.id.to_i)
        Strategy.update(moment.id, viewers: viewers)
      end
    end

    # Destroy allyship
    Allyship.find_by(user_id: current_user.id, ally_id: params[:ally_id]).destroy if !Allyship.find_by(user_id: current_user.id, ally_id: params[:ally_id]).nil?

    respond_to do |format|
      format.html { redirect_to params[:refresh] }
      format.json { head :no_content }
    end
  end

  private

  def if_not_signed_in
    if !user_signed_in?
      respond_to do |format|
        format.html { redirect_to new_user_session_path }
        format.json { head :no_content }
      end
    end
  end
end
