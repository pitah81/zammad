class Transaction
  def self.execute(options = {})
    if options[:reset_user_id] == true
      UserInfo.current_user_id = 1
    end
    original_interface_handle = ApplicationHandleInfo.current
    if options[:interface_handle]
      ApplicationHandleInfo.current = options[:interface_handle]
    end
    ActiveRecord::Base.transaction do
      PushMessages.init
      yield
      if options[:interface_handle]
        ApplicationHandleInfo.current = original_interface_handle
      end
      Observer::Transaction.commit(disable_notification: options[:disable_notification])
      PushMessages.finish
    end
  end
end
