# Sequel Basic Scafolding Model Generator for MySQL 
# Requires sequel-3.34.0 and above.
#
# This routine takes all the table of a database, en generates all Sequel models for Ramaze
# For each table model we put :
# - A header that reminds you the table structure
# - the plugin list you wrote in 'plugin_to_add' array
# - The Sequel referential inegrity : one_to_many, many_to_one
# - A "Validate" method that checks not nullable columnns and unique columns
# - Generates init.rb to be include in the project
#
# Note : db_connect.rb should already exists. Create it using Rake
# WARNING !
# This script is a very very very partial implementation of Sequel features
# It is only usefull at the beginning of a project to create all Sequel models of a database.
#
# StackOverflow question : http://stackoverflow.com/questions/10123818/does-a-sequel-models-generator-exists
# Thanks to Leucos : https://github.com/leucos
# Organisation : https://github.com/Erasme 

require 'sequel'

require_relative '../model/db_connect'

# Target dir
@model_dir_target = "../model"

# List of plugins to add to the model
plugin_to_add = [
  "validation_helpers",
  "json_serializer"
]

# International Error message
message_empty = "ne peut pas &ecirc;tre vide" # "cannot be empty"

# List of the tables we want to create scafolding Sequel model
models_to_create = DB.tables

############### Do not modify below ################

# Creating file and retreving a file pointer
def createfile(name)
  filename = File.join(@model_dir_target, name)
  if !File.exists?(filename)
    puts "creating #{filename}"
    File.new(filename, "w")
  else
    puts "#{filename} already exists."
  end
end

# Writing a nice header in files
def writeheader(f, title)
  f.puts "#coding: utf-8"
  f.puts "#"
  f.puts "# #{title}"
  f.puts "# generated #{Time.now.to_s} by #{$0}"
  f.puts "#"
end

# Write an association between two Models and manage special keys
def write_association(f, association_type, table_name, foreign_key)
  f.write(" #{association_type} :#{table_name}")
  # Specify column name if it is composite
  columns = foreign_key[:columns]
  if columns.length > 1
    f.write(", :key=>#{columns}")
  else
    # or if it does not respect the convention
    unless columns[0].to_s == "#{foreign_key[:table]}_id"
      f.write(", :key=>:#{columns[0]}")
    end
  end
  f.write("\n")
end

############### Main ################
models_to_create.each do |m|
  # Camelize table_name to create a ClassName
  modelName = m.to_s.split(/[^a-z0-9]/i).map{|w| w.capitalize}.join
  # model creation if it does not exists
  model = createfile(m.to_s + ".rb")
  next if model.nil?

  writeheader(model, "model for '#{m}' table")

  # HEADER : Table definition
  line = "# " << "-" * 30 << "+" << "-" * 21 << "+" << "-" * 10 << "+" << "-" * 10 << "+" << "-" * 12 << "+" << "-" * 20
  model.puts(line)
  model.puts("# COLUMN_NAME" << " " * 19 << "| DATA_TYPE" << " " * 11 << "| NULL? | KEY | DEFAULT | EXTRA")
  model.puts(line)
  DB.schema(m).each do |c|
      col = c[1]
      tab = 30 - c[0].to_s.size
      data_type = col[:db_type].to_s
      tab2 = 20 - data_type.size
      allow_null = col[:allow_null].to_s
      tab3 = 9 - allow_null.size
      column_key = ""
      if col[:primary_key]
        column_key = "PRI"
      else
        DB.indexes(m).each do |name, info|
          column_key = info[:unique] ? "UNI" : "MUL" if info[:columns].include?(c[0])
        end
      end
      tab4 = 9 - column_key.size
      default = col[:default].to_s
      tab5 = 11 - default.size
      extra = col[:auto_increment] ? "auto_increment" : ""
      model.puts("# #{c[0]}#{' '*tab}| #{data_type}#{' '*tab2}| #{allow_null}#{' '*tab3}| #{column_key}#{' '*tab4}| #{default}#{' '*tab5}| #{extra}")
  end
  model.puts line
  model.puts "#"
  model.puts "class #{modelName} < Sequel::Model(:#{m})"
  model.puts ""
  #
  # Add plugins
  #
  model.puts " # Plugins"
  plugin_to_add.each do |p|
    model.puts " plugin :#{p}"
  end
  model.puts ""
  #
  # Add table relationships
  #
  model.puts " # Referential integrity"
  # many_to_one relationships
  DB.foreign_key_list(m).each do |fk|
    write_association(model, "many_to_one", fk[:table], fk)
   end
  # one_to_many relationships
  # Need to look in each table's foreign_key
  # querying directly mysql is better here but let's do it totally with Sequel
  # Just for fun :)
  DB.tables.each do |t|
    unless t == m
      DB.foreign_key_list(t).each do |fk|
        write_association(model, "one_to_many", t, fk) if fk[:table] == m
      end
    end
  end

  model.puts ""
  #
  # Add Validate method
  #
  model.puts " # Not nullable cols"
  model.puts " def validate"
  list_of_not_nullable_cols = []
  #list_of_errors_messages = ""
  list_of_unique_val_cols = []
  # not nullable columns
  DB.schema(m).each do |c|
    info = c[1]
    list_of_not_nullable_cols.push(c[0]) unless info[:allow_null] or info[:primary_key]
  end

  # Unique columns
  DB.indexes(m).each do |name, info|
    if info[:unique]
      # There could be several columns for one index
      info[:columns].each do |col|
        list_of_unique_val_cols.push(col)
      end
    end
  end

  model.puts(" validates_presence #{list_of_not_nullable_cols}") unless list_of_not_nullable_cols.empty?
  model.puts(" validates_unique #{list_of_unique_val_cols}") unless list_of_unique_val_cols.empty?
  model.puts(" end\n")
  #
  # Add Referential integrity event
  #
  # delete cascade
  # update cascade
  model.puts "end"
  model.close
end


# then create the init.rb file
init = createfile("init.rb")
if !init.nil?
  writeheader(init, "include file to access all models")
  init.puts "require 'sequel'\n"
  init.puts "require_relative 'db_connect'\n"
  init.puts "# MODELS"
  models_to_create.each do |m|
    init.puts "require_relative '#{m}'"
  end
  init.close
end

puts "Done."
