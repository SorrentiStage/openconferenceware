# == Schema Information
# Schema version: 20120427185014
#
# Table name: events
#
#  id                                      :integer(4)      not null, primary key
#  title                                   :string(255)     
#  deadline                                :datetime        
#  open_text                               :text            
#  closed_text                             :text            
#  created_at                              :datetime        
#  updated_at                              :datetime        
#  proposal_status_published               :boolean(1)      not null
#  session_text                            :text            
#  tracks_text                             :text            
#  start_date                              :datetime        
#  end_date                                :datetime        
#  accept_proposal_comments_after_deadline :boolean(1)      
#  slug                                    :string(255)     
#  schedule_published                      :boolean(1)      
#  parent_id                               :integer(4)      
#  proposal_titles_locked                  :boolean(1)      
#  accept_selector_votes                   :boolean(1)      
#  show_proposal_confirmation_controls     :boolean(1)      
#

class Event < ActiveRecord::Base
  # Mixins
  ### Provide cached Snippet.lookup(id) method.
  include CacheLookupsMixin
  include SimpleSlugMixin

  cache_lookups_for :slug, :order => 'deadline desc', :include => [:tracks, :rooms]

  include SerializersMixin

  # Associations
  has_many :proposals, :order => 'submitted_at desc', :dependent => :destroy
  has_many :tracks, :order => 'title asc', :dependent => :destroy
  has_many :session_types, :dependent => :destroy
  has_many :rooms, :dependent => :destroy
  has_many :schedule_items, :dependent => :destroy, :order => 'start_time asc'
  has_many :children, :class_name => 'Event', :foreign_key => 'parent_id', :dependent => :destroy
  belongs_to :parent, :class_name => 'Event', :foreign_key => 'parent_id'
  has_many :selector_votes, :through => :proposals, :dependent => :destroy

  # Validations
  validates_presence_of \
    :slug,
    :title,
    :deadline,
    :open_text,
    :closed_text
  validates_uniqueness_of :slug
  validates_uniqueness_of :title

  # Is this event accepting proposals?
  def accepting_proposals?
    return Time.now < (self.deadline || Time.at(0))
  end
  
  # Returns an array of the dates when this event is happening.
  def dates
    if self.start_date.nil? || self.end_date.nil?
      return []
    else
      return (self.start_date.to_date .. self.end_date.to_date).to_a
    end
  end
  
  # Formats this event's dates for use in a select form control.
  def dates_for_select
    return [['','']] + self.dates.map{|date| [date.strftime("%B %d, %Y"), date.strftime("%Y-%m-%d")]}
  end
  
  # Determines if the event is currently taking place.
  def underway?
    self.start_date && self.end_date && (self.start_date..self.end_date).include?(Time.zone.now)
  end

  # Is this the current event?
  def current?
    return self == Event.current
  end

  # Return the current Event. Determines which event to return by checking to
  # see if a snippet says which is current, else tries to return the event
  # with the latest deadline, else returns a nil.
  def self.current
    query = lambda { self.current_by_settings || self.current_by_deadline }
    return self.cache_lookups? ?
      self.fetch_object('event_current', &query) :
      query.call
  end

  # Return current event by finding it by deadline.
  def self.current_by_deadline
    return Event.find(:first, :order => 'deadline desc')
  end

  # Return current event by finding it through SETTINGS global.
  # TODO Get the current event from an attribute in the Site object.
  def self.current_by_settings
    if slug = SETTINGS.current_event_slug
      begin
        return Event.find_by_slug(slug)
      rescue ActiveRecord::RecordNotFound
        return nil
      end
    else
      return nil
    end
  end

  # Return an array of this Event's Proposals with their Tracks for use by proposals#stats.
  def proposals_for_stats
    return self.proposals.find(
      :all, 
      :order => "created_at", 
      :select => "proposals.id, proposals.track_id, proposals.created_at, proposals.submitted_at, proposals.session_type_id",
      :include => [:track, :session_type])
  end

  # Return an array of the Event's ScheduleItems and Proposal sessions that
  # have been scheduled and given a room location. Optionally specify +is_admin+
  # to display schedule if it's not been published yet.
  def calendar_items(is_admin=false)
    results = []
    if self.schedule_published? || is_admin
      results += self.proposals.confirmed.scheduled.find(:all, :include => [:users, :room, :session_type, {:track => :event}])
    end
    results += self.schedule_items.find(:all, :include => [:room])
    results += (self.children.map{|child| child.calendar_items(is_admin)}.flatten)
    return results
  end
  
  # Return list of people that submitted to this event.
  def users
    return User.submitted_to(self)
  end
  
  # Return list of speakers for this event.
  def speakers
    return User.speaking_at(self)
  end

  # Return records for this event that are of the given +kind+ (e.g.,
  # :proposals or :sessions).
  def populated_proposals(kind=:proposals)
    case kind
    when :proposals
      return self.proposals.populated
    when :sessions
      return self.proposals.populated.confirmed
    else
      raise ArgumentError, "Unknown kind: #{kind}"
    end
  end

  # Return other Event objects.
  def other_events
    return self.class.find(:all, :order => "title asc", :select => "id, title").reject{|event| event == self}
  end

  # Return array of Rooms for this event and its parent event.
  def rooms_inherit
    return [self.parent.ergo.rooms, self.rooms].flatten.compact.sort_by(&:name)
  end

  # Return array of Tracks for this event, its parent, and its siblings.
  def tracks_combined
    return [self.tracks_descend, self.parent.ergo.tracks_descend].flatten.compact.uniq.sort_by(&:title)
  end
  
  # Return array of Tracks for this event and its children.
  def tracks_descend
    return (self.tracks + self.children.map(&:tracks)).flatten.uniq.sort_by(&:title)
  end

  # Return start_time for either self or parent Event.
  def start_date
    return self.parent_id ? self.parent.start_date : self.read_attribute(:start_date)
  end

  # Return end_time for either self or parent Event.
  def end_date
    return self.parent_id ? self.parent.end_date : self.read_attribute(:end_date)
  end

  # Return the parent event or this Event.
  def parent_or_self
    return self.parent_id ?
      self.parent :
      self
  end

  # Return all of this event's children and its children's children all the way down.
  def descendents
    return [self.children, self.children.map(&:descendents)].flatten.uniq
  end

  # Return the parent and all it's descendants
  def family
    return [self.parent_or_self, self.parent_or_self.descendents].flatten.uniq
  end

  # Return proposals that are related to this event, it's children or its parent.
  def related_proposals(some_proposals)
    returning([]) do |related|
      parent = self.parent_or_self
      for proposal in some_proposals
        catch :found do
          for an_event in self.family
            if proposal.event_id == an_event.id
              related << proposal
              throw :found
            end
          end
        end
      end
    end
  end
end
