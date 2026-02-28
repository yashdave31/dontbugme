# frozen_string_literal: true

module Dontbugme
  class TracesController < ActionController::Base
    layout 'dontbugme/application'

    before_action :ensure_enabled

    def index
      filters = { limit: 50 }
      filters[:status] = params[:status] if params[:status].present?
      filters[:kind] = params[:kind] if params[:kind].present?
      filters[:identifier] = params[:q] if params[:q].present?
      filters[:correlation_id] = params[:correlation_id] if params[:correlation_id].present?
      @traces = store.search(filters)
    end

    def show
      @trace = store.find_trace(params[:id])
      return render plain: 'Trace not found', status: :not_found unless @trace
    end

    def diff
      @trace_a = params[:a].present? ? store.find_trace(params[:a]) : nil
      @trace_b = params[:b].present? ? store.find_trace(params[:b]) : nil
      @diff_output = if @trace_a && @trace_b
        Dontbugme::Formatters::Diff.format(@trace_a, @trace_b)
      else
        nil
      end
    end

    private

    def store
      Dontbugme.store
    end

    def ensure_enabled
      return if Dontbugme.config.enable_web_ui

      render plain: 'Dontbugme Web UI is disabled. Set config.enable_web_ui = true to enable.', status: :forbidden
    end
  end
end
