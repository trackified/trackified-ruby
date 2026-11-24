# frozen_string_literal: true

module Trackified
  # Tracking status values (TrackingStatus in the OpenAPI spec).
  module TrackingStatus
    NOT_YET_SCANNED = "not_yet_scanned"
    IN_TRANSIT = "in_transit"
    OUT_FOR_DELIVERY = "out_for_delivery"
    AVAILABLE_FOR_PICKUP = "available_for_pickup"
    DELIVERED = "delivered"
    EXCEPTION = "exception"
    RETURNED = "returned"
    UNKNOWN = "unknown"
    ALL = [NOT_YET_SCANNED, IN_TRANSIT, OUT_FOR_DELIVERY, AVAILABLE_FOR_PICKUP, DELIVERED, EXCEPTION, RETURNED,
           UNKNOWN].freeze
  end

  # Event status values (EventStatus in the OpenAPI spec).
  module EventStatus
    INFO_RECEIVED = "info_received"
    IN_TRANSIT = "in_transit"
    OUT_FOR_DELIVERY = "out_for_delivery"
    AVAILABLE_FOR_PICKUP = "available_for_pickup"
    DELIVERED = "delivered"
    EXCEPTION = "exception"
    RETURNED = "returned"
    UNKNOWN = "unknown"
    ALL = [INFO_RECEIVED, IN_TRANSIT, OUT_FOR_DELIVERY, AVAILABLE_FOR_PICKUP, DELIVERED, EXCEPTION, RETURNED,
           UNKNOWN].freeze
  end

  # Webhook event types (WebhookEventType in the OpenAPI spec).
  module WebhookEventType
    TRACKING_CREATED = "tracking.created"
    TRACKING_UPDATED = "tracking.updated"
    TRACKING_STATUS_CHANGED = "tracking.status_changed"
    TRACKING_DELIVERED = "tracking.delivered"
    TRACKING_EXCEPTION = "tracking.exception"
    TRACKING_RETURNED = "tracking.returned"
    TRACKING_EXPIRED = "tracking.expired"
    ALL = [TRACKING_CREATED, TRACKING_UPDATED, TRACKING_STATUS_CHANGED, TRACKING_DELIVERED, TRACKING_EXCEPTION,
           TRACKING_RETURNED, TRACKING_EXPIRED].freeze
  end

  # Read-only wrapper around a JSON object. Declared fields get readers;
  # anything else the API returns stays reachable through #[] and #to_h.
  class Model
    # @param fields [Array<Symbol>]
    def self.fields(*names)
      names.each { |n| define_method(n) { @data[n.to_s] } }
    end

    # @param name [Symbol] reader name
    # @param klass [Class] model class for a nested object or array of objects
    def self.nested(name, klass)
      define_method(name) do
        v = @data[name.to_s]
        v.is_a?(Array) ? v.map { |x| klass.new(x) } : (v && klass.new(v))
      end
    end

    # @param data [Hash]
    def initialize(data)
      @data = (data || {}).transform_keys(&:to_s).freeze
    end

    # @return [Object] raw field value
    def [](key) = @data[key.to_s]
    # @return [Hash] the raw JSON object
    def to_h = @data
    def ==(other) = other.is_a?(self.class) && other.to_h == @data
    def inspect = "#<#{self.class.name} #{@data.inspect}>"
  end

  # One carrier scan. Tracking#events is newest first (guaranteed by the API).
  #
  # occurred_at without an offset is the local time where the scan happened; when the carrier gives an
  # offset it is included and time_zone_known is true.
  class TrackingEvent < Model
    fields :occurred_at, :time_zone_known, :status, :description, :location

    # @deprecated Use occurred_at. Sent until 2027-06-01, removed after that.
    def date = @data["date"]
  end

  # A tracked parcel.
  class Tracking < Model
    fields :id, :tracking_number, :carrier, :carrier_detected, :status, :estimated_delivery, :delivered_at,
           :delivered_at_time_zone_known, :delivery_detected_at, :exception, :service_level, :custom_id,
           :customer_email, :last_scraped_at, :next_scrape_at, :created_at, :updated_at
    # Newest first: sorted by occurred_at desc (guaranteed by the API); undated events keep their carrier
    # position after the dated ones.
    nested :events, TrackingEvent
  end

  # A carrier Trackified supports.
  class Carrier < Model
    fields :id, :mode, :regions, :tier, :aliases
    # The API returns displayName; the spec documents display_name. Accept both.
    def display_name = @data["display_name"] || @data["displayName"]
  end

  # Result of carriers.resolve. matched is "id", "alias", "name", "provider_slug" or "prefix".
  class CarrierResolution < Model
    fields :carrier, :name, :confidence, :matched
  end

  # A carrier guess from carriers.detect.
  class CarrierCandidate < Model
    fields :carrier, :confidence, :reason
  end

  # A webhook endpoint.
  class Webhook < Model
    # secret is only present in the create response.
    # previous_secret_expires_at is only present in the rotate_secret response.
    fields :id, :url, :event_types, :enabled, :secret_preview, :secret, :consecutive_failures, :created_at,
           :disabled_at, :previous_secret_expires_at

    # @param event [Event]
    # @return [Tracking] the tracking of any event type
    def self.tracking_of(event) = event.tracking
  end

  # One webhook delivery attempt record.
  class WebhookDelivery < Model
    # status is the HTTP status your endpoint returned.
    fields :id, :webhook_id, :url, :event_type, :status, :attempts, :error, :delivered_at, :created_at
  end

  # An API key. token is only present in the create response.
  class ApiKey < Model
    fields :id, :name, :prefix, :mode, :scopes, :token, :created_at, :last_used_at, :revoked_at
  end

  # Usage for the current billing period.
  class Usage < Model
    fields :period_start, :period_end, :plan, :trackings_used, :trackings_limit, :trackings_remaining,
           :rate_limit_per_minute, :webhook_deliveries, :carrier_volume
  end

  # A verified webhook event.
  #
  # data is {"tracking", "previous_status", "current_status"} for tracking.status_changed, and the tracking
  # itself for every other type. Use #tracking for either shape.
  class Event < Model
    fields :id, :type, :created_at
    # @return [Hash] the raw event payload
    def data = @data["data"]

    # @return [Boolean]
    def status_changed? = type == WebhookEventType::TRACKING_STATUS_CHANGED

    # @return [Tracking] the tracking, whatever the event type
    def tracking
      d = data || {}
      Tracking.new(status_changed? ? d["tracking"] : d)
    end

    # @return [String, nil] only for tracking.status_changed
    def previous_status = status_changed? ? data&.dig("previous_status") : nil
    # @return [String, nil] only for tracking.status_changed
    def current_status = status_changed? ? data&.dig("current_status") : nil
  end

  # One page of a list endpoint. Enumerable over every item across all pages.
  class Page < Model
    include Enumerable

    # @api private
    def initialize(data, klass, &fetch)
      super(data)
      @klass = klass
      @fetch = fetch
    end

    # @return [Array<Model>] items on this page only
    def data = (@data["data"] || []).map { |x| @klass.new(x) }
    # @return [Hash] {"limit","offset","total"}
    def pagination = @data["pagination"] || {}

    # @return [Boolean]
    def next_page?
      p = pagination
      items = @data["data"] || []
      !items.empty? && p["total"].is_a?(Integer) && p["offset"].to_i + items.size < p["total"]
    end

    # @return [Page, nil]
    def next_page
      return nil unless next_page? && @fetch

      @fetch.call(pagination["offset"].to_i + (@data["data"] || []).size)
    end

    # Yields every item on this page and all later pages.
    def each(&block)
      return enum_for(:each) unless block

      page = self
      while page
        page.data.each(&block)
        page = page.next_page
      end
    end
    alias auto_paging_each each
  end
end
