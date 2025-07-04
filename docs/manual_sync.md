# Manually Syncing your Accounts

#### Connect to bash shell of your maybe-app container

```sh
docker exec -it $(docker ps --filter "name=maybe-web" --format "{{.ID}}" | head -n1) bash
```

#### Start the rails console

```sh
bundle exec rails console
```

#### .sync_later each Family record

```ruby
Family.find_each do |family|
  family.sync_later(
    window_start_date: 1.day.ago,
    window_end_date: Time.current
  )
end
```

#### Alternatively, .sync_later each Account record

```ruby
Account.find_each do |account|
  account.sync_later(
    window_start_date: 1.day.ago,
    window_end_date: Time.current
  )
end
```

## One-Liner

```sh
docker exec -it $(docker ps --filter "name=maybe-web" --format "{{.ID}}" | head -n1) bash -c "bundle exec rails runner 'Family.find_each { |family| family.sync_later(window_start_date: 1.day.ago, window_end_date: Time.current) }'"
```

## Manually Clearing Syncs

```ruby
STALE_AFTER = 30.minutes # or whatever you'd like

Sync.where(status: [:pending, :syncing])
    .where("created_at < ?", STALE_AFTER.ago)
    .find_each do |sync|
      puts "Marking stale: #{sync.id}"
      sync.mark_stale!
    end
```

### Via /sidekiq

If you authenticate to your *web-fqdn*/sidekiq path (eg *https://mymaybe.tld/sidekiq*) with default credentials (`maybe`:`maybe`) you can enqueue the `clean_syncs` which marks >24hrs syncs stale

![image](https://github.com/user-attachments/assets/331c356f-6819-4312-9fe9-677c9d5be9a0)

