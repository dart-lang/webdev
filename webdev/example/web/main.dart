import 'package:angular/angular.dart';
import 'package:webdev_example_app/app_component.dart';
import 'main.template.dart' as ng;

main() {
  bootstrapStatic(AppComponent, [/*providers*/], ng.initReflector);
}
