# Configuration file for bot

(
  # Twitter API values
  consumer_key        => '',
  consumer_secret     => '',
  access_token        => '',
  access_token_secret => '',

  # given in seconds
  #  crontab is set to every six hours, this also enforces a minimum of 5
  #  in case I break crontab
  time_between_posts => 5 * 60 * 60,
);
