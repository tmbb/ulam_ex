data {
  int<lower=0> n;
  vector[n] x;
  vector[n] y;
}

parameters {
  real intercept;
  real<lower=0> error;
  real mu_x;
  real<lower=0> sigma_x;
}

model {
  for (i in 1:n) {
    x[i] ~ normal(mu_x, sigma_x);
    y[i] ~ normal(((x * slope) + intercept), error);
  }
}
