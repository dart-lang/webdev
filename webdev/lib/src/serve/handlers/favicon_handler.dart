// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';

Handler interceptFavicon(Handler handler) {
  return (request) async {
    var response = await handler(request);
    if (response.statusCode == 404 &&
        request.url.pathSegments.isNotEmpty &&
        request.url.pathSegments.last == 'favicon.ico') {
      unawaited(response.read().drain());
      return Response.ok(_icon);
    }
    return response;
  };
}

final _icon = gzip.decode(base64.decode(
    'H4sIAAAAAAAAE+3aTUgUYRgH8DGK0lN06BBBBkGG7Ye7JnrKPiAIjQ6GJX6trQtBRubOul'
    'bQHLNbiYcgEO2SsusmgiiIH4fsw2Z3O4hEdTUPBYoQKyRPM7PO9rKuOuvOvM+7o//l2cPw'
    'sju/h2fnZZbhuBzpVV7OSe/5XMFljjvKcVyBVNIhTuDix7ECMzdyIeIOQ9QD1CrccAkNTA'
    'TFzogfzc6AH9WO7Ee3I/qZsCP5mbEj+JmyU/YzZ6foZ9JOyQ+fPXlr4u0fa6ILWKrl6VqY'
    '6HQ8e3XXUqOldmpfjTyYi72vgdi7KmZqafw6vPaWQp+3THOla4/02A//nnKvsGgPdRSnVf'
    '2+krT8PY35h36O3FqOfahD92ZqT9cv22deXPi+Gr6P7tXDno5ftgd5i7gw1gyxjy50sx52'
    'rf5JQbZbRXn9atQHrPzuM7Vr8Q+0Hs9V7Qn/zE1T2LfzK3afTSTXs+DXy76Vf90eTl6P7d'
    'fTvpk/brdvsGP79ban8iv29tR2TL8R9mR/3O7Y1I7lN8pO+l96nAdC29gx/EbaSf+gz/Zc'
    'y3qafqPtqj/YduaE1vW0/DTsCb/X+oQlPy276h/0O+ZZ8dO0//c711jw07Yn5l/Ddd9oP4'
    'Zd9Qd46x1MP5Zd9Q+0Fh7B8mPaVb+8/0v3Ol20/dh20j/kO32Mpp8FO+lXZoC399Lws2JP'
    '9g94rSeN9rNkT/Yr9wHt9kGj/KzZU/kDbZYCI/ws2lP54zNQNK6nn1W7XAGvtXLD/198oV'
    '0vf7bZE3tBe9Fspv5stcf3AktZJv5stieuA37n1534zWBX/F7rxXT9ZrGvJyfkdy5q9ZvM'
    'Hp8B3lahxW9GuxxB4PaF/MV/tvKb1a4myJ+t3sxvdrucSaF8fyr/brCrCfC2JtK/m+xyRl'
    'pOHVT9SxNV6MaNdQ7GOisNsauRPvveyqc2GHpcyoC3GN4+LIFh4TyMPr0Kk121MNdX0WGU'
    'Xc6w4MybffMIprrrle/DrunuOgj31sPCqAv+zjZcM9KuRnneN9rUgv58L1lio2Ezz3wfEO'
    'zM9AHZToZ6Hxiyk6HSB0btZAzrQxbYyejahyyzk8m4D1lsJ7OjPpjETkZTHyKeX/DF5cA+'
    'V6MDUVc1RNz9EGn+JtUiRN1BEF1XsM9rL3vZi/nzD71EuTA+RAAA'));
