module Devise
  module Models
    module Async
      extend ActiveSupport::Concern

      included do
        # Register hook to send all devise pending notifications.
        #
        # When supported by the ORM/database we send just after commit to
        # prevent the backend of trying to fetch the record and send the
        # notification before the record is committed to the databse.
        #
        # Otherwise we use after_save.
        if respond_to?(:after_commit) # AR only
          after_commit :send_pending_devise_notifications
        else # mongoid
          after_save :send_pending_devise_notifications
        end
      end

      protected

      # This method overwrites devise's own `send_devise_notification`
      # to capture all email notifications and enqueue it for background
      # processing instead of sending it inline as devise does by
      # default.
      def send_devise_notification(notification, *args)
        return super unless Devise::Async.enabled

        if new_record? || saved_changes?
          pending_devise_notifications << [notification, args]
        else
          render_and_send_devise_message(notification, *args)
        end
      end

      private

      def send_pending_devise_notifications
        pending_devise_notifications.each do |notification, args|
          render_and_send_devise_message(notification, *args)
        end
    
        # Empty the pending notifications array because the
        # after_commit hook can be called multiple times which
        # could cause multiple emails to be sent.
        pending_devise_notifications.clear
      end
    
      def pending_devise_notifications
        @pending_devise_notifications ||= []
      end
    
      def render_and_send_devise_message(notification, *args)
        message = devise_mailer.send(notification, { class: self.class.name, id: id }, *args)
    
        # Deliver later with Active Job's `deliver_later`
        if message.respond_to?(:deliver_later)
          message.deliver_later
        else
          message.deliver_now
        end
      end
    end
  end
end
