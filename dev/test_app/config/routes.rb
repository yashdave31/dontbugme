# frozen_string_literal: true

Rails.application.routes.draw do
  root to: redirect('/inspector')
  mount Dontbugme::Engine, at: '/inspector'

  get 'seed', to: 'seed#index', as: :seed
end
