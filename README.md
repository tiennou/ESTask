# ESTask

A less exceptional NSTask replacement that can be used as a replacement with minimal changes. Also adds a few bells-and-whistles.

## Caveats

- Right now `-qualityOfService` does nothing.
- You might want to exchange `-(void)launch` with `-(BOOL)launch:(NSError **)error` for error-reporting.
- Threading is minimal. It should work as long as you don't pass instances around.