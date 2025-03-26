#lib/simplefil_to_maybe/utils.rb

require "active_support/all"
require 'io/console'

def convert_timestamp_to_mmddyyyy(input, tz = ENV["TIMEZONE"] || "UTC")
  time = Time.at(input)
  time_with_zone = time.in_time_zone(tz)
  return time_with_zone.strftime("%m/%d/%Y")
end

def convert_epoch_to_pg_timestamp(epoch)
  return Time.at(epoch).utc.strftime('%Y-%m-%d %H:%M:%S.%6N')
end

def get_first_of_month(epoch = false)
  now = Time.now
  first_of_month = Time.new(now.year, now.month, 1)
  if epoch
    return first_of_month.to_i
  else
    return convert_timestamp_to_mmddyyyy(first_of_month)
  end
end

def get_epoch_of_tomorrow()
  tomorrow = Time.now + (1 * 24 * 60 * 60)  # 1 day in seconds
  return tomorrow.to_i
end

# Function to display `print_property` of the `input_object`` and ask for user selection
def make_selection(input_object, print_property = "name", prompt = "Please select an object:", auto_select_single = false)

  if input_object.empty?
    puts "No input_object values specified!"
    return
  elsif auto_select_single && input_object.length == 1
    return input_object[0]
  end

  done = false

  while !done
    # Display the list of input_object
    puts ""
    puts prompt
    input_object.each_with_index do |item, index|
      puts "#{index + 1}. #{item[print_property]}"
    end
    puts "Q. Quit"

    # Ask for user input
    print "Enter the number of your selection: "
    selected = gets.chomp
    if selected.to_s.upcase == 'Q'
      done = true
      return nil
    else
      selected_index = selected.to_i - 1 # Convert input to zero-based index
    end

    # Validate the selection
    if selected_index >= 0 && selected_index < input_object.length
      selected_item = input_object[selected_index]
      done = true
      return selected_item
    else
      puts "Invalid selection, please try again."
    end
  end

  def get_purchase_price(cost_basis, share_count)
    return cost_basis / share_count
  end

end
