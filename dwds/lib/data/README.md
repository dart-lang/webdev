# How to generate data files:

## Creating a new data file:
1. Create a new file for your data type in the `/data` directory with the `.dart` extension
2. Create an abstract class for your data type (see existing files for examples)
3. Add the new data type to `/data/serializers.dart`
4 Run: `dart run build_runner build` from DWDS root (this will generate the `.g.dart` file)

## To update an existing data file:
1. Make your changes
2. Run: `dart run build_runner clean` from DWDS root
3. Run: `dart run build_runner build` from DWDS root 
