Rails.application.routes.draw do
  get "/up", to: proc { [200, {}, ["ok"]] }
  get "/hello", to: "hello#index"
end
