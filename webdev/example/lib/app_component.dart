import 'package:angular/angular.dart';

import 'src/hello_world/hello_world.dart';

@Component(
  selector: 'my-app',
  styleUrls: const ['app_component.css'],
  templateUrl: 'app_component.html',
  directives: const [HelloWorldComponent],
)
class AppComponent {
  // Nothing here.
}
