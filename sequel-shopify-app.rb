gem 'sequel'
gem 'pg'
gem 'sequel-rails', git: 'https://github.com/TalentBox/sequel-rails.git'
gem 'activeresource', git: 'https://github.com/rails/activeresource'
gem 'shopify_api'
gem 'shopify_api_mixins', git: 'https://github.com/mikeyhew/shopify_api_mixins'
gem 'shopify_app'
gem 'shopify_app_mixins', git: 'https://github.com/mikeyhew/shopify_app_mixins'
gem 'dotenv-rails'

initializer "shopify_api.rb", <<-CODE
ShopifyAPI::Connection.retry_on_429
ShopifyAPI::Connection.retry_on_5xx
CODE

file "config/database.yml", <<-CODE
default: &default
  adapter: postgresql
  port: 5432
  encoding: unicode
  pool: 5

development:
  <<: *default
  url: 'postgres://localhost/#{app_name}_development'

test:
  <<: *default
  url: 'postgres://localhost/#{app_name}_test'

production:
  <<: *default
  url: <%= ENV['DATABASE_URL'] %>
CODE

def generate_shop_model
  generate :model, 'shop', 'shopify_domain:string:uniq', 'shopify_token:string', '--no-migration'
  remove_file 'app/models/shop.rb'
  file 'app/models/shop.rb', <<-CODE
require 'shopify_app_mixins/sequel_session_storage'
class Shop < Sequel::Model
  include ShopifyAppMixins::SequelSessionStorage
end
CODE
  file "db/migrate/#{Time.now.utc.strftime('%Y%m%d%H%M%S')}_create_shops.rb", <<-CODE
Sequel.migration do
  change do
    create_table :shops do
      primary_key :id
      String :shopify_domain, null: false, unique: true
      String :shopify_token
    end
  end
end
CODE
end

def shopify_app_initializer
<<-CODE
ShopifyApp::SessionRepository.send :define_singleton_method, :load_storage do
  Shop
end

ShopifyApp.configure do |config|
  config.application_name = "My Sequel Shopify App"
  config.embedded_app = true
  config.api_key = ENV['SHOPIFY_API_KEY'] || (raise "Missing SHOPIFY_API_KEY")
  config.secret = ENV['SHOPIFY_SECRET'] || (raise "Missing SHOPIFY_SECRET")
  config.scope = 'write_products, write_orders'
  # webhooks_hostname = ENV['WEBHOOKS_HOSTNAME']
  # raise "Missing WEBHOOKS_HOSTNAME" unless webhooks_hostname.present?
  # config.webhooks = [
  #   # {topic: 'orders/create', address: "https://\#{webhooks_hostname}/webhooks/new_order"}
  # ]
end
CODE
end

after_bundle do
  run 'bin/spring stop' # sometimes it hangs if you don't do this
  generate_shop_model
  generate 'shopify_app:install'
  remove_file 'config/initializers/shopify_session_repository.rb'
  remove_file 'config/initializers/shopify_app.rb'
  initializer 'shopify_app.rb', shopify_app_initializer
  file ".env", <<-CODE
PORT
SHOPIFY_API_KEY
SHOPIFY_SECRET
CODE
  append_to_file ".gitignore", "# Ignore .env\n.env\n"
  git :init
  git add: '.'
  git commit: '-m initial'
  puts <<-MESSAGE

Conrats, you created an app! If you didn't see any error messages, then everything worked OK. Otherwise, there could be some problems.
Here are some things you still need to do:
  - Create a new Shopify app in the partners' dashboard. You need to paste your api key and shared secret into your `.env` file, which was created by this generator.
  - Set up `puma-dev` for this app. Choose a port number, and run `echo <port_number> > ~/.puma-dev/#{app_name}`, and set `PORT=<port_number>` in `.env`.
  - Set the OAuth callback for this app to `https://#{app_name}.dev/auth/shopify/callback`.
  - Add `force_ssl` to your `ApplicationController`, so that you don't end up with problems with `http` and `https` oauth callbacks not matching.
  - Either run `rails g shopify_app:home_controller` or create your own controller and root url. If you make your own controller, be sure to inherit from `ShopifyApp::AuthenticatedController`.

Other than that, you should be good to go. Happy coding!
MESSAGE
end
