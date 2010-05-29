module ScheduleOverlapsMixin
  def overlaps?(object)
    raise ArgumentError unless object.respond_to?(:start_time) && object.respond_to?(:end_time)
    if self.start_time != self.end_time && object.start_time != object.end_time
      (self.start_time..self.end_time).overlaps?(object.start_time..object.end_time) && (self.end_time != object.start_time && self.start_time != object.end_time)
    else
      self.start_time == object.start_time
    end
  end
end
