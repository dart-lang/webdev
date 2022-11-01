# How to generate data files:

## Creating a new data file:

1. Create a new file for your data type in the `/data` directory with the
   `.dart` extension
1. Create an abstract class for your data type (see existing files for examples)
1. Add the new data type to `/data/serializers.dart` 4 Run:
   `dart run build_runner build` from DWDS root (this will generate the
   `.g.dart` file)

## To update an existing data file:

1. Make your changes
1. Run: `dart run build_runner clean` from DWDS root
1. Run: `dart run build_runner build` from DWDS root
