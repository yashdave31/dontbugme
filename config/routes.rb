# frozen_string_literal: true

Dontbugme::Engine.routes.draw do
  root to: 'traces#index'
  get 'diff', to: 'traces#diff', as: :diff
  get ':id', to: 'traces#show', as: :trace, constraints: { id: /tr_[a-f0-9]+/ }
end
