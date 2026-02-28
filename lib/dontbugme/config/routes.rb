# frozen_string_literal: true

Rails.application.routes.draw do
  root to: 'traces#index', as: :root
  get 'diff', to: 'traces#diff', as: :diff
  get ':id', to: 'traces#show', as: :trace, constraints: { id: /tr_[a-f0-9]+/ }
end
