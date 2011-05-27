class Manage::EventsController < ApplicationController
  before_filter :require_admin
  before_filter :assert_current_event_or_redirect, :only => [:show, :edit, :update, :destroy]

  include BreadcrumbsMixin
  add_breadcrumb "Manage", "/manage"
  add_breadcrumb "Events", "/manage/events"

  # GET /events
  # GET /events.xml
  def index
    @events = Event.lookup

    respond_to do |format|
      format.html # index.html.erb
      format.xml  { render :xml => @events }
    end
  end

  # GET /events/1
  # GET /events/1.xml
  def show
    warn_about_incomplete_event

    add_breadcrumb @event.title, manage_event_path(@event)

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @event }
    end
  end

  # GET /events/new
  # GET /events/new.xml
  def new
    @event = Event.new
    if params[:parent_id]
      @event.parent_id = params[:parent_id]
    end

    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render :xml => @event }
    end
  end

  # GET /events/1/edit
  def edit
    @return_to = params[:return_to] || request.env["HTTP_REFERER"]
  end

  # POST /events
  # POST /events.xml
  def create
    @event = Event.new(params[:event])

    respond_to do |format|
      if @event.save
        flash[:notice] = 'Event was successfully created.'
        format.html { redirect_to(manage_event_path(@event)) }
        format.xml  { render :xml => @event, :status => :created, :location => @event }
      else
        format.html { render :action => "new" }
        format.xml  { render :xml => @event.errors, :status => :unprocessable_entity }
      end
    end
  end

  # PUT /events/1
  # PUT /events/1.xml
  def update
    @return_to = params[:return_to]

    respond_to do |format|
      if @event.update_attributes(params[:event])
        flash[:notice] = 'Event was successfully updated.'
        format.html { redirect_to(@return_to ? @return_to : [:manage, @event]) }
        format.xml  { head :ok }
      else
        format.html { render :action => "edit" }
        format.xml  { render :xml => @event.errors, :status => :unprocessable_entity }
      end
    end
  end

  # DELETE /events/1
  # DELETE /events/1.xml
  def destroy
    @event.destroy
    flash[:success] = "Destroyed event: #{@event.title}"

    respond_to do |format|
      format.html { redirect_to(manage_events_path) }
      format.xml  { head :ok }
    end
  end

  def proposals
    # NOTE: This is the bulk editor for the admin.
    @proposals = @event.proposals.populated
  end
end
