module SettingsHelper
  def simplefin_username_information
    information = []
    information << "64-character username, retrieved by exchanging your SimpleFIN Setup Token for an Access Token"
    information << "See https://beta-bridge.simplefin.org/info/developers for more details!"
    return information.join("\n")
  end

  def simplefin_password_information
    information = []
    information << "64-character password, retrieved by exchanging your SimpleFIN Setup Token for an Access Token"
    information << "See https://beta-bridge.simplefin.org/info/developers for more details!"
    return information.join("\n").html_safe
  end

  def maybe_postgres_host_information
    "Hostname or IP Address where your container is running"
  end

  def maybe_postgres_port_information
    "The port that is exposed on the PostgreSQL container/service"
  end

  def maybe_postgres_db_information
    "The name of your Maybe database"
  end

  def maybe_postgres_user_information
    "The user used to authenticate to the Maybe database"
  end

  def maybe_postgres_password_information
    "The password used to authenticate to the Maybe database"
  end

  def lookback_days_information
    "Number of days to look back for transactions"
  end

  def synchronization_schedule_information
    "Cron schedule expression for automatically syncing"
  end

  def institution_icons_information
    "Update the Maybe account icons for each institution retrieved from SimpleFIN"
  end
end
